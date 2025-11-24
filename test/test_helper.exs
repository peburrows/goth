{:ok, _} = Application.ensure_all_started(:bypass)

# Set up Mimic for mocking
Mimic.copy(ExAws.Config)
Mimic.copy(ExAws.STS)
Mimic.copy(ExAws.Auth)

ExUnit.start(exclude: [:integration])
