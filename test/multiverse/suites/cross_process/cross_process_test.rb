require 'test/unit'
require "rack/test"
require 'fake_collector'

class CrossProcessApp
  attr_accessor :response, :headers

  def call(env)
    [200, headers, [response]]
  end

  def reset_headers
    @headers = {'Content-Type' => 'text/html'}
  end
end


class CrossProcessTest < Test::Unit::TestCase

  # Important because the hooks are global that we only wire one of these up
  @@app = CrossProcessApp.new
  @@wrapped_app = NewRelic::Rack::AgentHooks.new(@@app)

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666 }}]
    $collector.run

    NewRelic::Agent.manual_start(
      :cross_process_id => "boo",
      :encoding_key => "\0",
      :trusted_account_ids => [1])

    @@app.reset_headers
    @@app.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  include Rack::Test::Methods

  def app
    @@wrapped_app
  end

  def test_cross_process_doesnt_modify_without_header
    get '/'
    assert_nil last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_process_doesnt_modify_with_invalid_header
    get '/', nil, {'X-NewRelic-ID' => Base64.encode64('otherjunk')}
    assert_nil last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_process_writes_out_information
    get '/', nil, {'X-NewRelic-ID' => Base64.encode64('1#234')}
    assert_not_nil last_response.headers["X-NewRelic-App-Data"]

    metric = NewRelic::Agent.instance.stats_engine.lookup_stats('ClientApplication/1#234/all')
    assert_equal 1, metric.call_count
  end
end

