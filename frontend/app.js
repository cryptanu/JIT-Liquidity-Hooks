const els = {
  startBlock: document.getElementById("startBlock"),
  preLaunchBlocks: document.getElementById("preLaunchBlocks"),
  launchBlocks: document.getElementById("launchBlocks"),
  initialMaxIn: document.getElementById("initialMaxIn"),
  steadyMaxIn: document.getElementById("steadyMaxIn"),
  maxImpact: document.getElementById("maxImpact"),
  bandWidth: document.getElementById("bandWidth"),
  jitUsage: document.getElementById("jitUsage"),
  deployBtn: document.getElementById("deployBtn"),
  initBtn: document.getElementById("initBtn"),
  runBtn: document.getElementById("runBtn"),
  steadyBtn: document.getElementById("steadyBtn"),
  addressLog: document.getElementById("addressLog"),
  blockVal: document.getElementById("blockVal"),
  phaseVal: document.getElementById("phaseVal"),
  blockedVal: document.getElementById("blockedVal"),
  slipVal: document.getElementById("slipVal"),
  phasePre: document.getElementById("phasePre"),
  phaseLaunch: document.getElementById("phaseLaunch"),
  phaseSteady: document.getElementById("phaseSteady"),
  swapRows: document.getElementById("swapRows"),
  chart: document.getElementById("slippageChart")
};

const state = {
  deployed: false,
  initialized: false,
  currentBlock: 100,
  blocked: 0,
  rows: [],
  baselineSlip: [],
  jitSlip: [],
  addresses: {}
};

const demand = [0.1, 0.25, 0.5, 0.75, 1.0, 2.0];

function params() {
  return {
    startBlock: Number(els.startBlock.value),
    preLaunchBlocks: Number(els.preLaunchBlocks.value),
    launchBlocks: Number(els.launchBlocks.value),
    initialMaxIn: Number(els.initialMaxIn.value),
    steadyMaxIn: Number(els.steadyMaxIn.value),
    maxImpact: Number(els.maxImpact.value),
    bandWidth: Number(els.bandWidth.value),
    jitUsage: Number(els.jitUsage.value)
  };
}

function phase(p) {
  const launchStart = p.startBlock + p.preLaunchBlocks;
  const steadyStart = launchStart + p.launchBlocks;
  if (state.currentBlock < launchStart) return "Prelaunch";
  if (state.currentBlock < steadyStart) return "Launch Discovery";
  return "Steady State";
}

function maxInForBlock(p) {
  const launchStart = p.startBlock + p.preLaunchBlocks;
  if (state.currentBlock < launchStart) return p.initialMaxIn;
  const elapsed = Math.min(Math.max(0, state.currentBlock - launchStart), p.launchBlocks);
  const t = p.launchBlocks === 0 ? 1 : elapsed / p.launchBlocks;
  return p.initialMaxIn + (p.steadyMaxIn - p.initialMaxIn) * t;
}

function randAddress() {
  return `0x${Array.from({ length: 40 }, () => Math.floor(Math.random() * 16).toString(16)).join("")}`;
}

function deploy() {
  state.deployed = true;
  state.addresses = {
    launchController: randAddress(),
    quoteVault: randAddress(),
    jitVault: randAddress(),
    issuance: randAddress(),
    hook: randAddress(),
    baselinePool: randAddress(),
    jitPool: randAddress()
  };
  els.addressLog.textContent = Object.entries(state.addresses)
    .map(([k, v]) => `${k}: ${v}`)
    .join("\n");
}

function initPools() {
  if (!state.deployed) return;
  state.initialized = true;
  state.rows = [];
  state.baselineSlip = [];
  state.jitSlip = [];
  state.blocked = 0;
  state.currentBlock = Number(els.startBlock.value);
  render();
}

function simulateRun() {
  if (!state.initialized) return;
  const p = params();
  const currentPhase = phase(p);

  if (currentPhase === "Prelaunch") {
    state.blocked += 1;
    state.rows.push({ amount: demand[0], baselinePrice: "-", jitPrice: "-", status: "Blocked: prelaunch" });
    state.currentBlock = p.startBlock + p.preLaunchBlocks;
  }

  const baselineRef = 1.0;
  let baselineFirst = 0;
  let jitFirst = 0;

  demand.forEach((amount, i) => {
    const baselineSlip = (amount / 4) * 1000;
    const baselinePrice = baselineRef * (1 + baselineSlip / 10000);

    if (!baselineFirst) baselineFirst = baselinePrice;
    const baselineDelta = Math.abs((baselinePrice - baselineFirst) / baselineFirst) * 10000;
    state.baselineSlip.push(Number(baselineDelta.toFixed(2)));

    const maxIn = maxInForBlock(p);
    const blocked = amount > maxIn;

    if (blocked) {
      state.blocked += 1;
      state.jitSlip.push(state.jitSlip.at(-1) || 0);
      state.rows.push({
        amount,
        baselinePrice: baselinePrice.toFixed(4),
        jitPrice: "-",
        status: "Blocked: maxAmountIn"
      });
      return;
    }

    const jitSlip = Math.max(0, baselineSlip * 0.55 - p.jitUsage * 20);
    const jitPrice = baselineRef * (1 + jitSlip / 10000);
    if (!jitFirst) jitFirst = jitPrice;
    const jitDelta = Math.abs((jitPrice - jitFirst) / jitFirst) * 10000;
    state.jitSlip.push(Number(jitDelta.toFixed(2)));

    state.rows.push({
      amount,
      baselinePrice: baselinePrice.toFixed(4),
      jitPrice: jitPrice.toFixed(4),
      status: "Executed"
    });

    if (i % 2 === 1) state.currentBlock += 1;
  });

  render();
}

function advanceSteady() {
  const p = params();
  state.currentBlock = p.startBlock + p.preLaunchBlocks + p.launchBlocks;
  render();
}

function render() {
  const p = params();
  const ph = phase(p);

  els.blockVal.textContent = state.currentBlock;
  els.phaseVal.textContent = ph;
  els.blockedVal.textContent = state.blocked;

  els.phasePre.classList.toggle("active", ph === "Prelaunch");
  els.phaseLaunch.classList.toggle("active", ph === "Launch Discovery");
  els.phaseSteady.classList.toggle("active", ph === "Steady State");

  const maxBaseline = Math.max(0, ...state.baselineSlip);
  const maxJit = Math.max(0, ...state.jitSlip);
  els.slipVal.textContent = `${(maxBaseline - maxJit).toFixed(2)} bps better`;

  els.swapRows.innerHTML = state.rows
    .map(
      (r, i) => `
      <tr>
        <td>${i + 1}</td>
        <td>${r.amount}</td>
        <td>${r.baselinePrice}</td>
        <td>${r.jitPrice}</td>
        <td>${r.status}</td>
      </tr>
    `
    )
    .join("");

  drawChart();
}

function drawChart() {
  const ctx = els.chart.getContext("2d");
  const w = els.chart.width;
  const h = els.chart.height;
  ctx.clearRect(0, 0, w, h);

  ctx.strokeStyle = "#1e3650";
  for (let i = 0; i < 6; i += 1) {
    const y = 24 + (h - 48) * (i / 5);
    ctx.beginPath();
    ctx.moveTo(36, y);
    ctx.lineTo(w - 18, y);
    ctx.stroke();
  }

  const all = [...state.baselineSlip, ...state.jitSlip, 1];
  const maxY = Math.max(...all);

  const draw = (series, color) => {
    if (!series.length) return;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    series.forEach((v, i) => {
      const x = 36 + ((w - 56) * i) / Math.max(1, demand.length - 1);
      const y = h - 24 - ((h - 48) * v) / maxY;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  };

  draw(state.baselineSlip, "#f97316");
  draw(state.jitSlip, "#22c55e");

  ctx.fillStyle = "#f97316";
  ctx.fillRect(40, 12, 10, 10);
  ctx.fillStyle = "#8ea2bd";
  ctx.fillText("Baseline", 56, 22);

  ctx.fillStyle = "#22c55e";
  ctx.fillRect(130, 12, 10, 10);
  ctx.fillStyle = "#8ea2bd";
  ctx.fillText("JIT", 146, 22);
}

els.deployBtn.addEventListener("click", deploy);
els.initBtn.addEventListener("click", initPools);
els.runBtn.addEventListener("click", simulateRun);
els.steadyBtn.addEventListener("click", advanceSteady);

render();
