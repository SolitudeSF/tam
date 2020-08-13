# Package

version       = "0.1.3"
author        = "SolitudeSF"
description   = "Tales of Maj'Eyal addon manager"
license       = "MIT"
srcDir        = "src"
bin           = @["tam"]


# Dependencies

requires "nim >= 1.0.0", "cligen >= 1.0.0", "nimquery >= 1.2.2", "tiny_sqlite#3fa5c0c8c14105be8a8f9f2bd93b60678d44a33f"
