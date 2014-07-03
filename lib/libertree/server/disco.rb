require 'libertree/server/responder/helper'

module Libertree
  module Server
    module Disco
      # XEP-0030: Service Discovery
      extend Libertree::Server::Responder::Helper

      private
      def self.disco_info(stanza)
        info = stanza.reply
        info.node = stanza.node

        # when node=:rule, the identity is considered a lambda to be evaluated for every node
        info.identities = @@identities[stanza.node] +
          @@identities[:rule].map {|rule| rule.call(stanza.node)}.compact.map {|id|
          Blather::Stanza::Iq::DiscoInfo::Identity.new(id)
        }
        info.features = @@features[stanza.node]

        @client.write info
      end

      public
      def self.register_feature(feature, node=nil)
        @@features[node] << feature
      end

      def self.register_identity(identity, node=nil)
        return  unless identity
        if ! identity.kind_of?(Proc)
          identity = Blather::Stanza::Iq::DiscoInfo::Identity.new(identity)
        end
        @@identities[node] << identity
      end

      def self.init(client)
        # set @client for the `respond` helper method
        @client = client

        # return a new empty array for each unknown key
        @@identities = {}
        @@identities.default_proc = proc {|h,k| h[k] = []}

        @@features = {}
        @@features.default_proc = proc {|h,k| h[k] = []}

        self.register_feature "http://jabber.org/protocol/disco#info"
        client.register_handler(:disco_info) {|stanza| disco_info(stanza)}
      end
    end
  end
end
