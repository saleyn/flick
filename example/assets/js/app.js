// app.js — BEFORE flick
// Polls /api/candles every second and updates the table via JSON.

function updateRow(candle) {
  const id  = "row-" + candle.symbol
  let   row = document.getElementById(id)

  if (!row) {
    row    = document.createElement("tr")
    row.id = id
    document.getElementById("rows").appendChild(row)
  }

  row.innerHTML = `
    <td>${candle.symbol}</td>
    <td>${candle.open}</td>
    <td>${candle.high}</td>
    <td>${candle.low}</td>
    <td>${candle.close}</td>
    <td>${candle.volume}</td>
  `
}

async function poll() {
  const resp    = await fetch("/api/candles")
  const candles = await resp.json()       // parse JSON on every tick
  candles.forEach(updateRow)
}

setInterval(poll, 1000)
poll()
