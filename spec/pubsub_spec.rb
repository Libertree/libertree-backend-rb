require 'blather'
require 'spec_helper'
require 'libertree/client'

describe Libertree::Server::PubSub do
  before :each do
    @client = LSR.connection
    @client.stub :write
    @jid = 'pubsub.liber.tree'
    Libertree::Server::PubSub.init(@client, @jid)
  end

  it 'advertises pubsub service' do
    msg = Blather::Stanza::Iq::DiscoInfo.new
    msg.to = @jid
    ns = msg.class.registered_ns

    expect( @client ).to receive(:write) do |stanza|
      # TODO: upstream bug: stanza.identities and stanza.features
      # always returns an empty array, unless inherited
      stanza = Blather::Stanza::Iq::DiscoInfo.new.inherit stanza
      identity = Blather::Stanza::Iq::DiscoInfo::Identity.
        new({ name: "Libertree PubSub", type: "service", category: "pubsub" })
      expect( stanza.identities ).to include(identity)

      expect( stanza.features.map(&:var) ).to include('http://jabber.org/protocol/pubsub',
                                                      'http://jabber.org/protocol/disco#items')
    end
    @client.handle_data msg
  end

  it 'reports collection or leaf info for pubsub nodes' do
    account = Libertree::Model::Account.create(FactoryGirl.attributes_for(:account))
    spring = Libertree::Model::Pool.create(
      FactoryGirl.attributes_for(:pool, member_id: account.member.id, sprung: true, name: 'whocares')
    )

    collection_nodes =
      [ "/users",
        "/groups",
        "/users/#{account.username}/springs",
      ]

    leaf_nodes =
      [ "/posts",
        "/users/#{account.username}/springs/#{spring.id}",
        "/users/#{account.username}/posts",
      ]

    collection_nodes.each do |node|
      msg = Blather::Stanza::Iq::DiscoInfo.new
      msg.to = @jid
      msg.node = node

      expect( @client ).to receive(:write) do |stanza|
        # TODO: upstream bug: stanza.identities and stanza.features
        # always returns an empty array, unless inherited
        stanza = Blather::Stanza::Iq::DiscoInfo.new.inherit stanza
        identity = Blather::Stanza::Iq::DiscoInfo::Identity.
          new({ type: "collection", category: "pubsub" })
        expect( stanza.identities ).to include(identity)
      end
      @client.handle_data msg
    end

    leaf_nodes.each do |node|
      msg = Blather::Stanza::Iq::DiscoInfo.new
      msg.to = @jid
      msg.node = node

      expect( @client ).to receive(:write) do |stanza|
        # TODO: upstream bug: stanza.identities and stanza.features
        # always returns an empty array, unless inherited
        stanza = Blather::Stanza::Iq::DiscoInfo.new.inherit stanza
        identity = Blather::Stanza::Iq::DiscoInfo::Identity.
          new({ type: "leaf", category: "pubsub" })
        expect( stanza.identities ).to include(identity)
      end
      @client.handle_data msg
    end

  end
end
