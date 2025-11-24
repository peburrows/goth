defmodule Goth.Token.ExAws do
  @moduledoc """
  AWS workload identity integration using ex_aws.

  This module provides AWS workload identity federation support by leveraging
  the existing ex_aws and ex_aws_sts libraries for credential resolution and
  AWS API integration.

  ## Dependencies

  This functionality requires the following optional dependencies:
  - `ex_aws ~> 2.1`

  If these dependencies are not available, AWS workload identity federation
  will not be supported, but other Goth functionality remains unaffected.

  ## Credential Sources Supported

  Through ex_aws, this module automatically supports:
  - EC2 Instance Metadata Service (IMDSv1 and IMDSv2)
  - ECS Task Credentials
  - AWS Lambda execution role
  - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.)
  - AWS CLI config files (~/.aws/credentials, ~/.aws/config)
  - IAM roles and assume role chains
  """

  require Logger

  @doc """
  Generates a subject token for AWS workload identity federation.

  This creates a signed GetCallerIdentity request using ex_aws that can be
  exchanged with Google's STS for an access token.

  ## Parameters

  - `audience` - The audience string to include in the signed request,
    typically the full resource name of the Google service account.

  ## Returns

  - `{:ok, subject_token}` - Base64-encoded signed request for Google STS
  - `{:error, reason}` - Error message, including missing dependencies
  """

  if Code.ensure_loaded?(ExAws) && Code.ensure_loaded?(ExAws.STS) do
    def generate_subject_token(audience) do
      with {:ok, signed_request} <- build_signed_request(audience) do
        {:ok, encode_for_google_sts(signed_request)}
      end
    end

    defp build_signed_request(audience) do
      url = "https://sts.amazonaws.com/"
      params = "Action=GetCallerIdentity&Version=2011-06-15"
      url = URI.parse(url) |> URI.append_query(params) |> URI.to_string()

      headers = [{"x-goog-cloud-target-resource", audience}]

      config = ExAws.Config.new(:sts)

      case ExAws.Auth.headers(:post, url, :sts, config, headers, "") do
        {:ok, signed_headers} ->
          request_details =
            %{
              "method" => "POST",
              "url" => url,
              "headers" => Map.new(signed_headers)
            }

          {:ok, request_details}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp encode_for_google_sts(signed_request) do
      token = %{
        "url" => signed_request["url"],
        "method" => signed_request["method"],
        "headers" =>
          Enum.map(signed_request["headers"], fn {key, value} ->
            %{"key" => key, "value" => value}
          end)
      }

      token
      |> Jason.encode!()
      |> url_quote()
    end

    defp url_quote(string) do
      string
      |> :uri_string.quote()
      |> to_string()
    end
  else
    def generate_subject_token(_audience) do
      {:error, "ex_aws dependency is required for AWS workload identity federation"}
    end
  end
end
