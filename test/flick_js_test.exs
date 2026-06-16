defmodule FlickJsTest do
  use ExUnit.Case, async: true

  @js_dir Path.join(__DIR__, "js")

  test "flick.js QUnit suite passes under node" do
    {output, exit_code} =
      System.cmd("node", ["run.js"], cd: @js_dir, stderr_to_stdout: true)

    assert exit_code == 0, """
    flick.js test suite failed:

    #{output}
    """
  end
end
