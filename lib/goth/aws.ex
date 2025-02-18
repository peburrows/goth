defmodule Goth.AWS do
  @moduledoc """
  Utility functions for interacting with GCP Workload Federation with AWS IAM
  as the identity provider.
  """

  @spec aws_iam_subject_token(String.t(), String.t(), String.t(), String.t(), map()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def aws_iam_subject_token(url, region_url, regional_cred_url_template, audience, config) do
    with {:ok,
          %{
            "AccessKeyId" => access_key_id,
            "SecretAccessKey" => secret_access_key,
            "Token" => token
          }} <- credentials_from_metadata(url, config),
         {:ok, region} <- region(region_url, config) do
      # template the URL
      url = String.replace(regional_cred_url_template, "{region}", region)

      # create our AWS client
      aws_conf =
        ExAws.Config.new(:sts,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          security_token: token,
          region: region
        )

      # sign the headers. note that the x-amz-content-hash header must not be
      # included due to this GCP bug: https://issuetracker.google.com/issues/190809963
      {:ok, sig_headers} =
        ExAws.Auth.headers(:post, url, :sts, aws_conf, [{"x-goog-cloud-target-resource", audience}], "")

      # return the signed request to GCP
      request = %{
        "url" => url,
        "method" => "POST",
        "headers" => for({key, value} <- sig_headers, do: %{"key" => key, "value" => value})
      }

      # this token must be URI encoded twice. once here, and once in the form body.
      Jason.encode!(request)
      # slashes (ASCII 47) must be left untouched
      |> URI.encode(fn char -> char == 47 or URI.char_unreserved?(char) end)
      |> then(&{:ok, &1})
    end
  end

  defp credentials_from_metadata(url, config) do
    # add a trailing slash if missing
    url =
      case String.ends_with?(url, "/") do
        true -> url
        false -> "#{url}/"
      end

    with {:ok, %{status: 200, body: instance_creds_path}} <-
           request(config.http_client, method: :get, url: url, headers: [], body: ""),
         # request the instance credentials
         {:ok,
          %{
            status: 200,
            body: instance_creds_body
          }} <- request(config.http_client, method: :get, url: "#{url}#{instance_creds_path}", headers: [], body: "") do
      Jason.decode(instance_creds_body)
    end
  end

  defp region(region_url, config) do
    # check the ENV var
    env_region = System.get_env("AWS_REGION")

    case env_region do
      nil ->
        # fetch the AZ from the AWS metadata API
        {:ok, %{status: 200, body: az}} =
          request(config.http_client, method: :get, url: region_url, headers: [], body: "")

        # trim the last character of the az off to get the region
        {:ok, String.slice(az, 0..-2//1)}

      env_region ->
        {:ok, env_region}
    end
  end

  defp request({:finch, extra_options}, options) do
    Goth.__finch__(options ++ extra_options)
  end

  defp request({mod, _} = config, options) when is_atom(mod) do
    Goth.HTTPClient.request(config, options[:method], options[:url], options[:headers], options[:body], [])
  end

  defp request({fun, extra_options}, options) when is_function(fun, 1) do
    fun.(options ++ extra_options)
  end
end
