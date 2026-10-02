defmodule Mix.Tasks.Axiom.Db.Setup do
  @moduledoc "Create the schema in the project-only local test database."
  use Mix.Task
  @shortdoc "Create tables only in the fixed project-local axiom test DB"
  def run(_) do
    Mix.Task.run("app.start")
    Axiom.TestDatabase.prepare!()
    Mix.shell().info("axiom test schema ready on 127.0.0.1:55439/axiom_test")
  end
end
