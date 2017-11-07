require "spec_helper"
require "uri"

describe Spree::Adyen::ApiResponse do
  let(:http_success) do
    instance_double(
      "Net::HTTPSuccess",
      body: "resultCode=Authorised&pspReference=1234567890",
    )
  end
  let(:http_redirect) do
    instance_double(
      "Net::HTTPSuccess",
      body: URI.encode_www_form({"resultCode"=>["RedirectShopper"],
                                 "md"=>["encryptedmd"],
                                 "paRequest"=>["encryptedpaReq"],
                                 "issuerUrl"=>
                                 ["https://test.adyen.com/hpp/3d/validate.shtml"],
                                 "pspReference"=>["1234567890"]})
    )
  end
  let(:http_failure) do
    instance_double(
      "Net::HTTPSuccess",
      body: URI.encode_www_form({"resultCode"=>["Refused"],
                                 "refusalReason"=>["Denied"],
                                 "response"=>["Modify failure"]})
    )
  end
  let(:http_error) do
    instance_double(
      "Net::HTTPInternalServerError",
      body: "Something went wrong"
    )
  end
  let(:api_redirect) { Adyen::REST::Response.new(http_redirect) }
  let(:api_success) { Adyen::REST::AuthorisePayment::Response.new(http_success) }
  let(:api_failure) { Adyen::REST::Response.new(http_failure) }
  let(:api_error) { Adyen::REST::ResponseError.new("ERROR") }

  before { allow(http_success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true) }
  before { allow(http_failure).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true) }
  before { allow(http_error).to receive(:is_a?).with(Adyen::REST::ResponseError).and_return(true) }

  describe "#psp_reference" do
    context "when the response was a server error" do
      subject { described_class.new(api_error).psp_reference }

      it { is_expected.to be nil }
    end

    context "when the response was not an error" do
      subject { described_class.new(api_success).psp_reference }

      it "returns the PSP reference from the API response" do
        expect(subject).to eq "1234567890"
      end
    end
  end

  describe "#attributes" do
    context "when the request caused a server error" do
      let(:api_error) { Adyen::REST::ResponseError.new("BOOM") }

      it "returns an empty hash" do
        expect(described_class.new(api_error).attributes).to eq({})
      end
    end

    context "when the request succeeded" do
      it "returns the response attributes" do
        expect(described_class.new(api_success).attributes).
          to eq ({ "resultCode" => "Authorised", "pspReference" =>"1234567890" })
      end
    end

    context "when the request returns a redirect" do
      it "returns the redirect attributes" do
        expect(described_class.new(api_redirect).attributes).
          to eq ({ "resultCode" => "RedirectShopper",
                   "md" => "encryptedmd",
                   "paRequest" => "encryptedpaReq",
                   "pspReference" => "1234567890",
                   "issuerUrl" => "https://test.adyen.com/hpp/3d/validate.shtml" })
      end
    end
  end

  describe "#message" do
    context "when the request was successful" do
      subject { described_class.new(api_success).message }

      it "returns the response attributes as JSON" do
        expect(subject).to eq "{\n  \"resultCode\": \"Authorised\",\n  \"pspReference\": \"1234567890\"\n}"
      end
    end

    context "when the request failed" do
      subject { described_class.new(gateway_response).message }

      context "and the request was an authorisation" do
        let(:gateway_response) { Adyen::REST::AuthorisePayment::Response.new(http_failure) }

        it "returns the refusal reason" do
          expect(subject).to eq "Denied"
        end
      end

      context "and the request was a modification" do
        let(:gateway_response) { Adyen::REST::ModifyPayment::Response.new(http_failure) }

        it "returns the response code" do
          expect(subject).to eq "Modify failure"
        end
      end

      context "and the request caused a server error" do
        let(:gateway_response) { Adyen::REST::ResponseError.new("BOOM") }

        it "returns the error message" do
          expect(subject).to eq "API request error: BOOM"
        end
      end
    end
  end
end
