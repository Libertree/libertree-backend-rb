require 'blather'
require 'spec_helper'
require 'libertree/client'

describe Libertree::Server::Responder do
  let(:helper_class) { Class.new }
  let(:helper) { helper_class.new }
  LSR = Libertree::Server::Responder

  before :each do
    helper_class.class_eval {
      include Libertree::XML::Helper
      include LSR::Helper
    }
    @server = mock
    @server.stub :id
  end

  it 'rejects unsupported iq stanzas with "UNKNOWN COMMAND"' do
    msg = Blather::Stanza::Iq.new :set
    response = LSR.error code: 'UNKNOWN COMMAND'

    c = LSR.send :client
    LSR.should_receive(:respond) do |args|
      args[:to].should eq msg
      args[:with].to_s.should eq response.to_s
    end

    c.send :call_handler_for, :iq, msg
  end

  # TODO
  it 'responds to any other unsupported stanza type with "UNKNOWN COMMAND"' do
    pending
  end

  it 'responds with "MISSING PARAMETER" when a handler throws MissingParameter' do
    msg = helper.build_stanza( "localhost.localdomain",
                               { 'post' => { 'id' => 10 }} )
    msg.from = "test.localdomain"
    response = LSR.error({ :code => 'MISSING PARAMETER',
                           :text => 'username'
                         })

    c = LSR.send :client
    LSR.should_receive(:respond) do |args|
      args[:to].should eq msg
      args[:with].to_s.should eq response.to_s
    end

    # handler throws :halt to prevent falling through to the catch-all handler
    catch(:halt) { c.send :call_handler_for, :iq, msg }
  end

  it 'responds with "NOT FOUND" when a handler throws NotFound' do
    h = { 'comment' => {
        'id'         => 999,
        'username'   => 'nosuchusername',
        'public_key' => "WHATEVER",
        'post_id'    => 1234,
        'text'       => 'A test comment.',
      }}

    subject.instance_variable_set(:@server, @server)

    msg = helper.build_stanza( "localhost.localdomain", h )
    msg.from = "test.localdomain"
    response = LSR.error({ :code => 'NOT FOUND',
                           :text => 'Unrecognized member username: "nosuchusername"'})

    c = LSR.send :client
    LSR.should_receive(:respond) do |args|
      args[:to].should eq msg
      args[:with].to_s.should eq response.to_s
    end

    # handler throws :halt to prevent falling through to the catch-all handler
    catch(:halt) { c.send :call_handler_for, :iq, msg }
  end

  it 'calls the correct handler for all valid iq commands' do
    LSR::VALID_COMMANDS.each do |command|
      stanza = helper.build_stanza("localhost.localdomain", { command => { id: 0 }})
      stanza.from = "test.localdomain"
      c = LSR.send(:client)
      c.stub :write
      LSR.should_receive "rsp_#{command.gsub('-', '_')}".to_sym
      catch(:halt) { c.send :call_handler_for, :iq, stanza }
    end
  end

  # TODO
  it 'rejects malformed stanzas with "BAD REQUEST"' do
    pending
    #c = LSR.send(:client)
    #expect { c.receive_data "hello" }.
    #  not_to raise_error
  end

  context "when the requester is not a member of any of the receiver's forests" do
    include_context 'requester not in any forest'

    it 'responds with UNRECOGNIZED SERVER' do
      LSR::VALID_COMMANDS.reject {|c| c == 'forest'}.each do |command|
        stanza = helper.build_stanza("localhost.localdomain", { command => { id: 0 }})
        stanza.from = "test.localdomain"

        err = LSR.error code: 'UNRECOGNIZED SERVER'

        c = LSR.send(:client)
        LSR.should_receive(:respond) do |args|
          args[:with].to_s.should eq err.to_s
        end
        c.send :call_handler_for, :iq, stanza
      end
    end

    it 'does not respond with UNRECOGNIZED SERVER to "forest" commands' do
      stanza = helper.build_stanza("localhost.localdomain",
                                   { 'forest' => { "whatever" => "whatever" }})
      stanza.from = "test.localdomain"

      err = LSR.error code: 'UNRECOGNIZED SERVER'

      c = LSR.send(:client)
      LSR.should_receive(:respond) do |args|
        args[:with].to_s.should_not eq err.to_s
      end
      c.send :call_handler_for, :iq, stanza
    end
  end

  describe 'respond' do
    it 'writes a reply to the stream' do
      msg = Blather::Stanza::Iq.new :set
      c = LSR.send(:client)
      c.should_receive(:write)
      LSR.respond to: msg
    end

    it 'appends a given XML node to the reply' do
      msg = Blather::Stanza::Iq.new :set
      node = Nokogiri::XML.fragment "<custom>whatever</custom>"
      reply = msg.reply
      reply.add_child node

      c = LSR.send :client
      c.should_receive(:write).with reply
      LSR.respond to: msg, with: node
    end
  end

  describe 'process' do
    it 'calls valid commands with parameters' do
      xml = Nokogiri::XML.fragment helper.params_to_xml({ 'id' => 10 })
      hash = helper.xml_to_hash xml
      LSR.should_receive(:rsp_post).with(hash)
      LSR.process("post", xml)
    end

    it 'converts commands with dashes to method names with underscores' do
      xml = Nokogiri::XML.fragment helper.params_to_xml({ 'id' => 10 })
      hash = helper.xml_to_hash xml
      LSR.should_receive(:rsp_post_like_delete).with(hash)
      LSR.process("post-like-delete", xml)
    end
  end

  describe 'error' do
    it 'builds an XML document with the given error code' do
      err = LSR.error( code: "SOME CODE" ).
        serialize(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
      err.should eq "<error><code>SOME CODE</code></error>"
    end

    it 'builds an XML document with the given error message' do
      err = LSR.error( code: "ERROR", text: "Some message" ).
        serialize(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
      err.should eq "<error><code>ERROR</code><text>Some message</text></error>"
    end
  end
end