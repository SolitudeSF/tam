# Package

version       = "0.1.0"
author        = "SolitudeSF"
description   = "Tales of Maj'Eyal addon manager"
license       = "MIT"
srcDir        = "src"
bin           = @["tam"]


# Dependencies

requires "nim >= 1.0.0", "cligen >= 1.0.0", "nimquery >= 1.2.2", "tiny_sqlite#0b7c1a59cf7b722d7df3079a90ad84a742942c71"
