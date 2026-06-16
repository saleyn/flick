// app.js — AFTER flick
// Replaced HTTP polling with a persistent ETF WebSocket.
// The setInterval poll and fetch() call are gone entirely.

function updateRow(candle) {
  const id  = "row-" + candle.symbol.value   // atoms arrive as ErlAtom
  let   row = document.getElementById(id)

  if (!row) {
    row    = document.createElement("tr")
    row.id = id
    document.getElementById("rows").appendChild(row)
  }

  row.innerHTML = `
    <td>${candle.symbol.value}</td>
    <td>${candle.open}</td>
    <td>${candle.high}</td>
    <td>${candle.low}</td>
    <td>${candle.close}</td>
    <td>${candle.volume}</td>
  `
}

// Appended by mix flick.install — edited to dispatch to updateRow:
const _flickProto = location.protocol === "https:" ? "wss" : "ws"
const _flickUrl   = `${_flickProto}://${location.host}/ws?symbol=AAPL`
const _flickWs    = new WebSocket(_flickUrl)
_flickWs.binaryType = "arraybuffer"
_flickWs.onmessage = (event) => {
  const candle = window.Flick.decode(event.data)
  updateRow(candle)
}
