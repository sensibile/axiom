Code.compiler_options(ignore_module_conflict: true)
Code.compile_string(File.read!("lib/axiom/store.ex") |> String.replace("REPEATABLE READ READ ONLY", "READ COMMITTED READ ONLY"))
Code.require_file("verification/fresh-bundle-independent-20261002/probe.exs")
