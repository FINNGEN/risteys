// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";

/*
 * Hooks: Phoenix <--> JS
 */
let Hooks = {};

/*
 * Risteys
 */
import { drawCompBox } from "./CompBox.js";
import { plot as varBinPlot } from "./varBinPlot.js";
import { drawPlot as drawPlotCumulInc } from "./cumulincPlot.js";
import { openDialog, closeDialog, setupDialogComponent } from "./dialog.js";
import { plotAllObs } from "./plotting.js";

/* Dialog / modal */
// Making the dialog functions available globally
window.openDialog = openDialog;
window.closeDialog = closeDialog;
setupDialogComponent();

/* CSV download
 *
 * Triggered by a LiveView `push_event(socket, "download-csv", %{filename, content})`,
 * which LiveView dispatches as a `phx:download-csv` window event. We build a Blob from
 * the server-generated CSV and trigger a download client-side.
 */
window.addEventListener("phx:download-csv", (event) => {
  const { filename, content } = event.detail;
  const blob = new Blob([content], {
    type: "text/csv;charset=utf-8;",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
});

/* Draw histograms */
const histograms = document.querySelectorAll("[data-histogram-values");
for (const ee of histograms) {
  const xLabel = ee.dataset.histogramXAxisLabel;
  const yLabel = ee.dataset.histogramYAxisLabel;
  const barColor = ee.dataset.histogramPlotBarColor;
  const values = JSON.parse(ee.dataset.histogramValues);
  const selector = "#" + ee.id;

  varBinPlot(selector, values, xLabel, yLabel, barColor);
}

/* Draw Cumulative Incidence Functions */
const cif_plots = document.querySelectorAll("[data-cif-data]");
for (const ee of cif_plots) {
  const selector = "#" + ee.id;
  const data = JSON.parse(ee.dataset.cifData);
  if (data.length > 0) {
    // 'data' will be '[]' when there is no CIF to show
    drawPlotCumulInc(selector, data);
  }
}

/* Draw all Observable Plot plots */
plotAllObs();

/* Draw CompBoxes
 *
 * For them to allways appear we would need to:
 * 1. draw when the static HTML is rendered by Phoenix
 * 2. draw on LiveView 'mounted'
 * 3. draw on LiveView 'updated'
 *
 * However, we don't do (1.) here because the initial static render is intentionally rendering
 * 0 elements to prevent blocking the initial page render (it takes ~ 5s to render).
 * So instead we just do (2.) and (3.)
 */
function replaceWithCompBox(element) {
  // The element MUST have a 'data-compbox-value'
  const value = element.dataset.compboxValue;
  element.innerHTML = drawCompBox(value);
}

Hooks.DrawCompBox = {
  mounted() {
    replaceWithCompBox(this.el);
  },
  updated() {
    replaceWithCompBox(this.el);
  },
};

/*
 * UTILS
 */
function init_search_key() {
  document.addEventListener("keyup", (event) => {
    const isInputText =
      document.activeElement.tagName === "INPUT" &&
      document.activeElement.type === "text";
    const isTextarea = document.activeElement.tagName === "TEXTAREA";
    if (!isInputText && !isTextarea && event.key === "s") {
      let search_box = document.getElementById("search-input");
      search_box.focus();
    }
  });
}

init_search_key();

/***********
 * Phoenix *
 **********/
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
