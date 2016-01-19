defmodule GoogleAuthTest do
  use ExUnit.Case
  doctest GoogleAuth

  test "setting and retrieving values" do
    GoogleAuth.set("key", "123")
    assert {:ok, "123"} == GoogleAuth.get("key")
  end
end
