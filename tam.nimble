# Package

version       = "0.1.4"
author        = "SolitudeSF"
description   = "Tales of Maj'Eyal addon manager"
license       = "MIT"
srcDir        = "src"
bin           = @["tam"]


# Dependencies

requires "nim >= 1.0.0", "cligen >= 1.0.0", "nimquery >= 1.2.3", "tiny_sqlite#8fe760d91da18faecdbe32a7038bfd4661bcf1b6"
