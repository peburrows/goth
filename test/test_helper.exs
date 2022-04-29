{:ok, _} = Application.ensure_all_started(:hackney)
{:ok, _} = Application.ensure_all_started(:bypass)

ExUnit.start()
