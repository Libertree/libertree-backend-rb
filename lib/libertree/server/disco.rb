require 'libertree/server/responder/helper'

module Libertree
  module Server
    module Disco
      # XEP-0030: Service Discovery
      extend Libertree::Server::Responder::Helper

      private
      @@identities = []
      @@features = [ "http://jabber.org/protocol/disco#info" ]

      def self.disco_info(stanza)
        info = stanza.reply
        info.identities = @@identities
        info.features = @@features
        @client.write info
      end

      public
      def self.register_feature(feature)
        @@features << feature
      end

      def self.register_identity(identity)
        @@identities << identity
      end

      def self.init(client)
        # set @client for the `respond` helper method
        @client = client
        client.register_handler(:disco_info) {|stanza| disco_info(stanza)}
      end
    end
  end
end
