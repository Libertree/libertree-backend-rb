require 'json'
require 'em-websocket'
require 'libertree/server'

module Libertree
  module Server
    module Websocket

      $sessions = Hash.new

      def self.log(message)
        Libertree::Server.log "[websocket] #{message}"
      end

      def self.run(conf)
        config = if conf['secure_websocket']
          {
            :host => conf['websocket_listen_host'],
            :port => conf['websocket_port'],
            :secure => true,
            :tls_options => {
              :private_key_file => conf['websocket_ssl_private_key'],
              :cert_chain_file => conf['websocket_ssl_cert']
            }
          }
        else
          {
            :host => conf['websocket_listen_host'],
            :port => conf['websocket_port'],
          }
        end

        EventMachine::WebSocket.run(config) {|ws| self.server(ws)}
        [:notifications, :chat_messages, :comments, :notifications_updated, :comment_deleted].each do |channel|
          EventMachine.defer do
            Libertree::DB.dbh.listen(channel, :loop => true) { |channel, _, payload|
              self.handle(channel, payload)
            }
          end
        end
        self.heartbeat
        EventMachine.add_periodic_timer(0.1) do
          # Ensures that EventMachine ticks at least as often as this.
          # Otherwise, websocket data flushing/sending can take a long time for
          # no good reason.  (It seems to flush data along with the heartbeat
          # timer.)
          # We don't actually have to do anything in this block.
        end
      end

      def self.server(ws)
        ws.onopen do
        end

        ws.onclose do
          $sessions.each do |sid,session_data|
            session_data[:sockets].delete ws
          end
        end

        ws.onmessage do |json_data|
          begin
            self.onmessage ws, JSON.parse(json_data)
          rescue Exception => e
            Libertree::Server::Websocket.log e.message
            Libertree::Server::Websocket.log e.backtrace.join("\n\t")
            raise e
          end
        end

        ws.onerror do |error|
          Libertree::Server::Websocket.log "ERROR: #{error.inspect}"
        end
      end

      def self.onmessage(ws, data)
        sid = data['sid']
        session_account = Libertree::Model::SessionAccount[sid: sid]
        if session_account.nil?
          Libertree::Server::Websocket.log "Unrecognized session: #{sid}"
          return
        end

        $sessions[sid] ||= {
          sockets: Hash.new,
          account: session_account.account,
        }

        $sessions[sid][:sockets][ws] ||= {
          last_post_id: session_account.account.rivers_not_appended.reduce({}) {|acc, river|
            last_post = river.posts({:limit => 1}).first
            if last_post
              acc[river.id] = last_post.id
            else
              acc[river.id] = Libertree::DB.dbh[ "SELECT MAX(id) FROM posts" ].single_value
            end
            acc
          },
          last_notification_id: Libertree::DB.dbh[ "SELECT MAX(id) FROM notifications WHERE account_id = ?", session_account.account.id ].single_value,
          last_comment_id: Libertree::DB.dbh[ "SELECT MAX(id) FROM comments" ].single_value,
          last_chat_message_id: Libertree::DB.dbh[
            "SELECT MAX(id) FROM chat_messages WHERE to_member_id = ? OR from_member_id = ?",
            session_account.account.member.id,
            session_account.account.member.id
          ].single_value,
        }
      end

      def self.heartbeat
        EventMachine.add_periodic_timer(60) do
          $sessions.each do |sid,session_data|
            session_data[:sockets].each do |ws,socket_data|

              ws.send({ 'command'   => 'heartbeat',
                        'timestamp' => Time.now.strftime('%H:%M:%S'),
                      }.to_json)
            end
          end
        end
      end

      def self.handle(channel, payload)
        case channel
        when 'notifications'
          self.handle_notifications
        when 'notifications_updated'
          self.handle_notifications_update
        when 'chat_messages'
          self.handle_chat_messages
        when 'comments'
          self.handle_comments
        when 'comment_deleted'
          self.handle_comment_deleted payload
        else
          Libertree::Server::Websocket.log "No handler for channel: #{channel}"
        end
      end

      def self.handle_notifications
        $sessions.each do |sid,session_data|
          session_data[:sockets].each do |ws,socket_data|
            account = session_data[:account]
            account.dirty

            notifs = Libertree::Model::Notification.s(
              "SELECT * FROM notifications WHERE id > ? AND account_id = ? ORDER BY id LIMIT 1",
              socket_data[:last_notification_id],
              account.id
            )
            notifs.each do |n|
              if account.num_notifications_unseen == 0
                # TODO: i18n is not in the backend yet
                # title = _('No notifications')
                title = 'No notifications'
              else
                # TODO: i18n is not in the backend yet
                # title = n_('1 notification', '%d notifications', account.num_notifications_unseen) % account.num_notifications_unseen
                title = "#{account.num_notifications_unseen} notification(s)"
              end
              ws.send(
                {
                  'command' => 'notification',
                  'id' => n.id,
                  'n' => account.num_notifications_unseen,
                  'iconTitle' => title,
                }.to_json
              )
              socket_data[:last_notification_id] = n.id
            end
          end
        end
      end

      def self.handle_notifications_update
        $sessions.each do |sid,session_data|
          session_data[:sockets].each do |ws,socket_data|
            account = session_data[:account]
            account.dirty

            num = account.num_notifications_unseen

            if num == 0
              # TODO: i18n is not in the backend yet
              # title = _('No notifications')
              title = 'No notifications'
            else
              # TODO: i18n is not in the backend yet
              # title = n_('1 notification', '%d notifications', num) % num
              title = "#{num} notification(s)"
            end

            ws.send(
              {
                'command' => 'notification',
                'n' => num,
                'iconTitle' => title,
              }.to_json
            )
          end
        end
      end

      def self.handle_chat_messages
        $sessions.each do |sid,session_data|
          session_data[:sockets].each do |ws,socket_data|
            account = session_data[:account]
            account.dirty

            chat_messages = Libertree::Model::ChatMessage.where(
              "id > ? AND ( to_member_id = ? OR from_member_id = ? )",
              socket_data[:last_chat_message_id],
              account.member.id,
              account.member.id
            ).exclude(
              from_member_id: account.ignored_members.map(&:id)
            ).order(:id)

            chat_messages.each do |cm|
              partner = cm.partner_for(account)
              ws.send(
                {
                  'command'             => 'chat-message',
                  'id'                  => cm.id,
                  'partnerMemberId'     => partner.id,
                  'numUnseen'           => account.num_chat_unseen,
                  'numUnseenForPartner' => account.num_chat_unseen_from_partner(partner),
                  'ownMessage'          => cm.from_member_id == account.member.id,
                }.to_json
              )
              socket_data[:last_chat_message_id] = cm.id
            end
          end
        end
      end

      def self.handle_comments
        $sessions.each do |sid,session_data|
          session_data[:sockets].each do |ws,socket_data|
            account = session_data[:account]
            account.dirty

            comments = Libertree::Model::Comment.comments_since_id( socket_data[:last_comment_id] )
            comments.each do |c|
              ws.send(
                {
                  'command'   => 'comment',
                  'commentId' => c.id,
                  'postId'    => c.post.id,
                }.to_json
              )
              socket_data[:last_comment_id] = c.id
            end
          end
        end
      end

      def self.handle_comment_deleted(payload)
        payload =~ /^(\d+),(\d+)$/
        comment_id, post_id = Regexp.last_match[1], Regexp.last_match[2]

        $sessions.each do |sid,session_data|
          session_data[:sockets].each do |ws,socket_data|
            account = session_data[:account]
            account.dirty

            ws.send(
              {
                'command'   => 'comment-deleted',
                'commentId' => comment_id,
                'postId'    => post_id,
              }.to_json
            )
          end
        end
      end
    end
  end
end
