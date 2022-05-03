# CHANGELOG

## v1.3.0-dev (unreleased)

* Add `Goth.start_link/1`, `Goth.fetch/2`, and `Goth.Token.fetch/1`.

Deprecations:

* `Goth.Token`: Deprecate `for_scope/2`, `from_response_json/2`, `refresh!/1`
* Deprecate `Goth.Client` module
* Deprecate `Goth.Config` module
* Deprecate `Goth.TokenStore` module

### Changes from v1.3.0-rc.3

  * Self-signed JWT claim overrides (#105)
  * Improve retry logic (#127)
  * Improve fetching and prefetching logic (#128)
  * Add :audience option when fetching from metadata server (#121)
  * Simplify the refresh scheduling - replace `:refresh_before` with `:refresh_after` (#131)
  * Simplify http client contract (#129)
  * Add Goth.fetch!/2
