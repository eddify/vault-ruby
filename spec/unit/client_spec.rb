require "spec_helper"

module Vault
  describe Client do
    let(:client) { subject }

    context "configuration" do
      it "is a configurable object" do
        expect(client).to be_a(Configurable)
      end

      it "users the default configuration" do
        Defaults.options.each do |key, value|
          expect(client.send(key)).to eq(value)
        end
      end

      it "uses the values in the initializer" do
        client = described_class.new(address: "http://new.address")
        expect(client.address).to eq("http://new.address")
      end

      it "can be modified after initialization" do
        expect(client.address).to eq(Defaults.address)
        client.address = "http://new.address"
        expect(client.address).to eq("http://new.address")
      end
    end

    describe "#get" do
      it "delegates to the #request_with_retries method" do
        expect(subject).to receive(:request_with_retries).with(:get, "/foo", {}, {})
        subject.get("/foo")
      end
    end

    describe "#post" do
      let(:data) { double }

      it "delegates to the #request method" do
        expect(subject).to receive(:request).with(:post, "/foo", data, {})
        subject.post("/foo", data)
      end
    end

    describe "#put" do
      let(:data) { double }

      it "delegates to the #request_with_retries method" do
        expect(subject).to receive(:request_with_retries).with(:put, "/foo", data, {})
        subject.put("/foo", data)
      end
    end

    describe "#patch" do
      let(:data) { double }

      it "delegates to the #request method" do
        expect(subject).to receive(:request).with(:patch, "/foo", data, {})
        subject.patch("/foo", data)
      end
    end

    describe "#delete" do
      it "delegates to the #request_with_retries method" do
        expect(subject).to receive(:request_with_retries).with(:delete, "/foo", {}, {})
        subject.delete("/foo")
      end
    end

    describe "#to_query_string" do
      it "converts spaces to + characters" do
        params = { emoji: "sad panda" }
        expect(subject.to_query_string(params)).to eq("emoji=sad+panda")
      end
    end

    context "#request_with_retries" do
      let(:retry_options) { { :retry_options => [Vault::HTTPServerError, :attempts => 1, :base => 0.00] } }

      it "delegates to #request method when :retry_options is nil" do
        expect(subject).to_not receive(:with_retries)
        expect(subject).to receive(:request).with(:get, "/foo", {}, {})
        subject.request_with_retries(:get, "/foo")
      end

      it "delegates to #request method composed in #with_retry block when :retry_options is not nil" do
        allow(subject).to receive(:options).and_return(subject.options.merge(retry_options))
        expect(subject).to receive(:request).with(:get, "/foo", {}, {})
        expect(subject).to receive(:with_retries).with(*retry_options[:retry_options]).and_call_original
        subject.request_with_retries(:get, "/foo")
      end
    end

    context "#with_retries" do
      let(:options) do
        {
          attempts: 1,
          base:     0.00,
          max_wait: 1.0,
        }
      end

      before { subject.address = "https://vault.test" }

      Vault::Client::RESCUED_EXCEPTIONS.each do |e|
        it "retries on #{e}" do
          stub_request(:get, "https://vault.test/")
            .to_raise(e).then
            .to_return(status: 200, body: "{}")

          subject.with_retries(Vault::HTTPConnectionError, options) do
            subject.get("/")
          end
        end

        it "raises after maximum attempts on #{e}" do
          stub_request(:get, "https://vault.test/")
            .to_raise(e)

          expect {
            subject.with_retries(Vault::HTTPConnectionError, options) do
              subject.get("/")
            end
          }.to raise_error(Vault::HTTPConnectionError)
        end

        break
      end

      (400..422).each do |code|
        it "does not retry on a #{code} response code" do
          wrong_error = StandardError.new("bad")
          stub_request(:get, "https://vault.test/")
            .to_return(status: code)
            .to_raise(wrong_error)

          expect {
            subject.get("/")
          }.to raise_error(Vault::HTTPClientError)
        end
      end

      (500..520).each do |code|
        it "retries on a #{code} response code" do
          stub_request(:get, "https://vault.test/")
            .to_return(status: code).then
            .to_return(status: 200, body: "{}")

          subject.with_retries(Vault::HTTPError, options) do
            subject.get("/")
          end
        end

        it "raises after maximum attempts on #{code}" do
          stub_request(:get, "https://vault.test/")
            .to_return(status: code, body: "#{code}")
          expect {
            subject.with_retries(Vault::HTTPServerError, options) do
              subject.get("/")
            end
          }.to raise_error(Vault::HTTPServerError)
        end
      end
    end
  end
end
