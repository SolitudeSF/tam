import os, httpclient, htmlparser, xmltree, strutils, times, tables, uri, terminal, asyncdispatch, asyncfile
import tiny_sqlite, cligen, nimquery

type
  AddonInfo = object
    name: string
    timestamp: int64
    enabled: bool

const
  tomeUrl = "https://te4.org/"
  addonsUrl = tomeUrl & "games/addons/tome/"
  searchUrl = tomeUrl & "addons/tome?s="

  selectorTime = ".views-row-first .views-field-changed"
  selectorLink = ".views-row-first .views-field-phpcode a"

func idToFilename(id: string): string = "tome-" & id & ".teaa"
func idToUrl(id: string): string = addonsUrl & id.encodeUrl

proc getInfoHtml(http: AsyncHttpClient, id: string): Future[XmlNode] {.async.} =
  result = http.getContent(id.idToUrl).await.parseHtml

func isValidAddon(n: XmlNode): bool =
  not n[1][1][7][0].text.startsWith("T-Engine4 Games | Tales of Maj")

func getName(n: XmlNode): string =
  n[1][3][7][1][1][3][0][0].text

proc getTimestamp(n: XmlNode, q: Query): int64 =
  q.exec(n, single = true)[0].innerText.strip.
    parseTime("yyyy-MM-dd hh:mm", utc()).toUnix

proc getLink(n: XmlNode, q: Query): string =
  tomeUrl & q.exec(n, single = true)[0].attr("href")

proc installFile(src, dst: string) =
  # when defined(windows):
  when true:
    copyFile src, dst
  else:
    createSymlink src, dst

proc performInstall(id: string, queryTime, queryLink: Query,
  dataDir, tomeDir: string, db: DbConn, disabled: bool) {.async.} =
  let
    http = newAsyncHttpClient()
    info = await http.getInfoHtml id
  if info.isValidAddon:
    let
      name = info.getName
      timestamp = info.getTimestamp(queryTime)
      link = info.getLink(queryLink)
      data = await http.getContent link
      filename = id.idToFilename
      src = dataDir / filename
      dst = tomeDir / filename
      srcFile = openAsync(src, fmWrite)
    await srcFile.write data
    if not disabled:
      installFile src, dst
    db.transaction:
      db.exec "INSERT INTO Addons(id, name, timestamp, enabled) VALUES(?, ?, ?, ?)",
        id, name, timestamp, not disabled
    echo "Installed " & id
  else:
    stderr.writeLine "Addon " & id & " wasn't found."

proc performUpdate(id: string, addon: AddonInfo, db: DbConn,
  queryTime, queryLink: Query, dataDir: string) {.async.} =
  let
    http = newAsyncHttpClient()
    info = await http.getInfoHtml id
    timestamp = info.getTimestamp(queryTime)
    link = info.getLink(queryLink)
  if timestamp > addon.timestamp:
    let
      data = await http.getContent link
      filename = id.idToFilename
      src = dataDir / filename
      srcFile = openAsync(src, fmWrite)
    await srcFile.write data
    close srcFile
    db.transaction:
      db.exec "UPDATE Addons SET timestamp = ? WHERE id = ?", timestamp, id
    echo "Updated " & id

proc getInstalledAddons(db: DbConn): Table[string, AddonInfo] =
  for row in db.iterate("SELECT id, name, timestamp, enabled FROM Addons"):
    result.add fromDbValue(row[0], string),
      AddonInfo(name: fromDbValue(row[1], string),
                timestamp: fromDbValue(row[2], int64),
                enabled: fromDbValue(row[3], bool))

proc initDb(dir: string): DbConn =
  result = openDatabase dir / "tam.db"
  result.exec """
  CREATE TABLE IF NOT EXISTS Addons(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    enabled INTEGER NOT NULL
  );"""

proc initDataDir(name: string): string =
  when defined(windows):
    result = getHomeDir() / "." & name
  else:
    result = getEnv("XDG_DATA_HOME", getHomeDir() / ".local/share") / name
  createDir result

proc getTomeDir: string = getHomeDir() / ".t-engine" / "4.0" / "addons"

proc enable(addons: seq[string]) =
  ## Enable addons
  if addons.len == 0:
    stderr.writeLine "You need to provide at least 1 addon id."
    quit 1

  let
    dataDir = initDataDir("tam")
    tomeDir = getTomeDir()
    db = initDb dataDir
    installed = db.getInstalledAddons

  for id in addons:
    if id in installed:
      let addon = installed[id]
      if addon.enabled:
        stderr.writeLine "Addon " & id & " is already enabled."
      else:
        let
          filename = id.idToFilename
          src = dataDir / filename
          dst = tomeDir / filename
        installFile src, dst
        db.transaction:
          db.exec "UPDATE Addons SET enabled = 1 WHERE id = ?", id
        echo "Enabled " & id
    else:
      stderr.writeLine "Addon " & id & " is not installed."

proc disable(addons: seq[string]) =
  ## Disable addons
  if addons.len == 0:
    stderr.writeLine "You need to provide at least 1 addon id."
    quit 1

  let
    dataDir = initDataDir("tam")
    tomeDir = getTomeDir()
    db = initDb dataDir
    installed = db.getInstalledAddons

  for id in addons:
    if id in installed:
      let addon = installed[id]
      if addon.enabled:
        let
          filename = id.idToFilename
          dst = tomeDir / filename
        removeFile dst
        db.transaction:
          db.exec "UPDATE Addons SET enabled = 0 WHERE id = ?", id
        echo "Disabled " & id
      else:
        stderr.writeLine "Addon " & id & " is already disabled."
    else:
      stderr.writeLine "Addon " & id & " is not installed."

proc install(addons: seq[string], disabled = false) =
  ## Install addons
  if addons.len == 0:
    stderr.writeLine "You need to provide at least 1 addon id."
    quit 1

  let
    dataDir = initDataDir("tam")
    tomeDir = getTomeDir()
    db = initDb dataDir
    installed = db.getInstalledAddons
    queryTime = parseHtmlQuery(selectorTime)
    queryLink = parseHtmlQuery(selectorLink)

  var installs: seq[Future[void]]

  for id in addons:
    if id in installed:
      stderr.writeLine "Addon " & id & " is already installed."
    else:
      installs.add performInstall(id, queryTime, queryLink, dataDir, tomeDir, db, disabled)

  waitFor all installs

proc uninstall(addons: seq[string]) =
  ## Uninstall addons
  if addons.len == 0:
    stderr.writeLine "You need to provide at least 1 addon id."
    quit 1

  let
    dataDir = initDataDir("tam")
    tomeDir = getTomeDir()
    db = initDb dataDir
    installed = db.getInstalledAddons

  for id in addons:
    if id in installed:
      let
        addon = installed[id]
        filename = id.idToFilename
        src = dataDir / filename

      removeFile src

      if addon.enabled:
        let dst = tomeDir / filename
        removeFile dst

      db.transaction:
        db.exec "DELETE FROM Addons WHERE id = ?", id

    else:
      stderr.writeLine "Addon " & id & " is not installed."

proc update =
  ## Update installed addons
  let
    dataDir = initDataDir("tam")
    db = initDb dataDir
    installed = db.getInstalledAddons
    queryTime = parseHtmlQuery(selectorTime)
    queryLink = parseHtmlQuery(selectorLink)

  var
    updates = newSeq[Future[void]](installed.len)
    i = 0

  for id, addon in installed:
    updates[i] = performUpdate(id, addon, db, queryTime, queryLink, dataDir)
    inc i

  waitFor all updates

proc list(enabled = false, disabled = false, short = false) =
  ## List installed addons
  let
    all = not (enabled xor disabled)
    enabled = all or enabled
    disabled = all or disabled
    dataDir = initDataDir("tam")
    db = initDb dataDir
    installed = db.getInstalledAddons

  for id, info in installed:
    if enabled and info.enabled:
      if short:
        echo id
      else:
        styledEcho fgGreen, "[x] ", fgDefault, styleBright, info.name,
          resetStyle, "  ", styleDim, id, " ", $info.timestamp
    elif disabled and not info.enabled:
      if short:
        echo id
      else:
        styledEcho fgRed, "[ ] ", fgDefault, styleBright, info.name,
          resetStyle, "  ", styleDim, id, " ", $info.timestamp

proc query(addon: seq[string]) =
  ## List addon information
  if addon.len != 1:
    stderr.writeLine "Provide exactly one info query."
    quit 1

  let
    dataDir = initDataDir("tam")
    db = initDb dataDir
    installed = db.getInstalledAddons
    id = addon[0]

  if id in installed:
    let addon = installed[id]
    styledEcho(
      styleBright, "id: ", resetStyle, id,
      styleBright, "\nname: ", resetStyle, addon.name,
      styleBright, "\ntimestamp: ", resetStyle, $addon.timestamp,
      styleBright, "\nenabled: ", resetStyle, $addon.enabled,
      styleBright, "\nurl: ", resetStyle, id.idToUrl
    )
  else:
    stderr.writeLine "Addon " & id & " is not installed."

proc search(query: seq[string]) =
  ## Search addons on te4.org
  if query.len != 1:
    stderr.writeLine "Provide exactly one search query."
    quit 1

  let
    http = newHttpClient()
    data = http.getContent(searchUrl & query[0].encodeUrl)
    html = data.parseHtml
    results = html[1][3][7][1][1][5][1][15][1][3]

  if results[1].len == 2:
    echo "No items available."
  else:
    for n in countup(1, results.len - 1, 2):
      let
        result = results[n]
        href = result[0][0].attr("href")
        id = href[href.rfind('/') + 1..^1]
      styledEcho(
        styleBright, "Name: ", resetStyle, result[0][0][0].text,
        styleBright, "\nid: ", resetStyle, id,
        styleBright, "\nLast Updated: ", resetStyle, result[2].innerText,
        styleBright, "\nAuthor: ", resetStyle, result[3][0].innerText,
        styleBright, "\nURL: ", resetStyle, id.idToUrl, "\n"
      )

proc tam =
  clCfg.version = "0.1.4"
  dispatchMulti(
    ["multi", doc = "Tales of Maj'Eyal addon manager\n\n"],
    [install, help = {"disabled": "install addons in disabled state"}],
    [uninstall],
    [enable],
    [disable],
    [update],
    [list, help = {"enabled": "display only enabled addons",
                   "disabled": "display only disabled addons",
                   "short": "display only id of an addon"}],
    [query],
    [search]
  )

tam()
