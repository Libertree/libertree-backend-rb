require 'blather'
require 'spec_helper'
require 'libertree/client'

describe Libertree::Server::PubSub do
  LSR = Libertree::Server::Responder

  before :each do
    @client = LSR.connection
    @client.stub :write
    Libertree::Server::PubSub.init(@client, 'pubsub.liber.tree')
  end

  it 'advertises pubsub service' do
    msg = Blather::Stanza::Iq::DiscoInfo.new
    msg.to = @gateway
    ns = msg.class.registered_ns

    expect( @client ).to receive(:write) do |stanza|
      # upstream bug: stanza.identities and stanza.features always
      # returns an empty array
      expect( stanza.xpath('.//ns:identity[@name="Libertree PubSub" and @type="service" and @category="pubsub"]',
                           :ns => ns) ).not_to be_empty

      features = stanza.xpath('.//ns:feature/@var', :ns => ns).map(&:value)
      expect( features ).to include('http://jabber.org/protocol/pubsub',
                                    'http://jabber.org/protocol/disco#items')
    end
    @client.handle_data msg
  end

  it 'reports collection or leaf info for pubsub nodes' do
    # TODO: create dummy account with spring and test posts
    Libertree::DB.dbh.execute 'TRUNCATE accounts CASCADE'
    account = Libertree::Model::Account.create({
      username: "username",
      password_encrypted: BCrypt::Password.create("1234")
    })
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
      msg.to = @gateway
      msg.node = node
      ns = msg.class.registered_ns

      expect( @client ).to receive(:write) do |stanza|
        # upstream bug: stanza.identities and stanza.features always
        # returns an empty array
        expect( stanza.xpath('.//ns:identity[@type="collection" and @category="pubsub"]',
                             :ns => ns) ).not_to be_empty
      end
      @client.handle_data msg
    end

    leaf_nodes.each do |node|
      msg = Blather::Stanza::Iq::DiscoInfo.new
      msg.to = @gateway
      msg.node = node
      ns = msg.class.registered_ns

      expect( @client ).to receive(:write) do |stanza|
        # upstream bug: stanza.identities and stanza.features always
        # returns an empty array
        expect( stanza.xpath('.//ns:identity[@type="leaf" and @category="pubsub"]',
                             :ns => ns) ).not_to be_empty
      end
      @client.handle_data msg
     end

  end
end
