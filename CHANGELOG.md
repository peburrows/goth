# Changelog

## v1.4.3 (2024-01-15)

  * Update Finch to 0.17

## v1.4.2 (2023-08-24)

  * Update jose dependency
  * Require Elixir 1.11+

## v1.4.1 (2023-06-27)

  * change to OS time to prevent unmanagable clock skew

## v1.4.0 (2023-03-23)

  * Load config from `~/.config/gcloud/configurations/config_default`

## v1.3.1 (2022-08-10)

  * Force refresh whenever cached token is expired
  * Fix getting tokens from metadata with no options provide

## v1.3.0 (2022-06-29)

  * Add `Goth.start_link/1`, `Goth.fetch/2`, `Goth.fetch!/2`, and `Goth.Token.fetch/1`.

Deprecations:

  * `Goth.Token`: Deprecate `for_scope/2`, `from_response_json/2`, `refresh!/1`
  * Deprecate `Goth.Client` module
  * Deprecate `Goth.Config` module
  * Deprecate `Goth.TokenStore` module
