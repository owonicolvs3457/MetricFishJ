//-----------------------------------------------------------------------------------------//
//                                                                                         //
//                                   MetricFishJ v2.4 (EN)                                   //
//                                                                                         //
//              ImageJ macros: 44 morphometric measurements from                           //
//                            33 landmarks.                                                 //
//            Results in .xls (Excel) or .txt.                                             //
//                                                                                         //
//                                OWO Nicolas Roland, 2026                                        //
//                  Based on MorFishJ (Mattia Ghilardi) - github.com/mattiaghilardi        //
//                                                                                         //
//-----------------------------------------------------------------------------------------//

var MetricFishJ_version = "v1", ImageJ_version = "1.53s";
var v = versionCheck();
var lastPlacedIndex = -1;

// Track completed steps for "Continue" function
var scale_done = false;
var adjust_done = false;
var orient_done = false;
var outline_done = false;
var lines_done = false;
var landmarks_done = false;
var optional_done = false;
var resuming = false;
var lineNames = newArray("D", "A", "H", "E");
var side = "";
var outlineroi = -1;
var derived_done = false;
var yB = 0, yC = 0, yF = 0, yG = 0;
var APoints = newArray(0);
var lineX = newArray(4);
var inBatch = false;
// Batch processing context: declared here (not just assigned inside
// multiAnalysis()/runBatchFrom()) so it can NEVER be "undefined" if
// continueAnalysis() accesses it in an inconsistent state (e.g. batch
// interrupted before these values were actually set).
var imgFolder = "";
var imgNames = newArray(0);
// batchIdx (NOT "i": "i" is used as a throwaway loop variable without "var"
// in several functions - extrema/intersection/areaXline/straightenRotate -
// all called DURING morphoAnalysis(). If the batch index were named "i", it
// would get clobbered by the first of those functions called during resume,
// before even reaching the batch-resume logic in continueAnalysis()).
var batchIdx = -1;
var nProcessed = 0;
var stopNow = false;

function resetAnalysisFlags() {
  scale_done = false;
  adjust_done = false;
  orient_done = false;
  outline_done = false;
  lines_done = false;
  derived_done = false;
  landmarks_done = false;
  optional_done = false;
  resuming = false;
  // placeHistory is NEVER cleared elsewhere: without this line, a 2nd image
  // (batch, or a 2nd "Single image" run in the same session) would inherit
  // the PREVIOUS image's history. Concrete consequence: ticking "Go back to
  // previous landmark" on the very 1st landmark of the new image would wrongly
  // jump to the LAST landmark of the previous image instead of there being no
  // checkbox at all (nothing to go back to). Reset here only (never inside
  // continueAnalysis(), which must instead PRESERVE the history for a genuine
  // resume).
  placeHistory = newArray(0);
}

function versionCheck() {
    requires(ImageJ_version);
    return 1;
}

//-------------------------------- UTILITY FUNCTIONS  -------------------------------------//

function skipImage() {
  message = "Write a remark about the image if needed,\n" +
            "or tick 'Skip image' to ignore it\n" +
            "and move to the next one, then click OK.";
  Dialog.create("Image quality");
  Dialog.setInsets(0, 0, 5);
  Dialog.addMessage(message);
  Dialog.addString("Remark", "", 30);
  Dialog.addCheckbox("Skip image", false);
  Dialog.show();
  remark = Dialog.getString();
  skip = Dialog.getCheckbox();
  return newArray(remark, skip);
}

function checkImage(type) {
  list = getList("image.titles");
  if (type == "m" && list.length > 0) {
    exit("<html><center>Close all images before<br>"
       + "starting a batch analysis.</center>");
  } else if (type == "s" && list.length == 0) {
    exit("<html><center>Open an image before starting<br>"
       + "a single-image analysis.</center>");
  } else if (type == "s" && list.length > 1) {
    exit("<html>Several images are open");
  }
}

function listImages(folder) {
  list = getFileList(folder);
  exts = newArray(".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp");
  imgs = newArray(0);
  for (i = 0; i < list.length; i++) {
    lower = toLowerCase(list[i]);
    ok = false;
    for (e = 0; e < exts.length; e++) {
      if (endsWith(lower, exts[e])) ok = true;
    }
    if (ok) imgs = Array.concat(imgs, list[i]);
  }
  Array.sort(imgs);
  return imgs;
}

var titleWithExt = "", title = "", copy = "";
function duplicateImage() {
  original = getImageID;
  titleWithExt = getTitle();
  // File.nameWithoutExtension tracks the last file touched by a File.*
  // function, NOT the active image: the GUI's run("Install...") makes it point
  // to macros.ijm. So the name is extracted from getTitle() instead, which is reliable.
  dotIndex = lastIndexOf(titleWithExt, ".");
  if (dotIndex == -1) { title = titleWithExt; } else { title = substring(titleWithExt, 0, dotIndex); }
  run("Duplicate...", " ");
  copy = getImageID;
  rename(title);
  selectImage(original);
  run("Close");
}

var h = 0, w = 0, ymid = 0, xmid = 0;
function getImageSize() {
  h = getHeight;
  w = getWidth;
  ymid = h / 2;
  xmid = w / 2;
}

function getOrientation() {
  Dialog.create("Orientation");
  label = "Which way is the fish facing?";
  items = newArray("left", "right");
  Dialog.addRadioButtonGroup(label, items, 1, 2, "left");
  Dialog.show();
  return Dialog.getRadioButton();
}

// "getScale": Define the image scale (optional)
var pxcm = "NA", length = "NA", lengthType = "NA";
var unitFactor = 1;   // unite de sortie / cm : mm=10, cm=1, inch=1/2.54
function getScale() {
  // Mandatory reset: without it, an image that picks "No scale available"
  // (or "Reference object") silently inherits pxcm/length/lengthType from the
  // previous image in the same session (morphoAnalysis() recomputes pxcm from
  // length as soon as length != "NA", whatever option is chosen here).
  pxcm = "NA";
  length = "NA";
  lengthType = "NA";
  unitFactor = 1;
  Dialog.create("Image scale");
  label = "Choose how to define the image scale.";
  items = newArray("Reference object", "Known fish length", "No scale available");
  Dialog.addRadioButtonGroup(label, items, 3, 1, "Reference object");
  Dialog.show();
  option = Dialog.getRadioButton();
  if (option == "Reference object") {
    getRefScale();
  } else if (option == "Known fish length") {
    getFishLength();
  }
}

function getRefScale() {
  do {
    run("Select None");
    setTool("Line");
    run("Line Width...", "line=1");
    message = "Trace a line over a reference\n" +
              "object of known length.";
    waitForUser("Reference scale", message);
    if (selectionType != 5) {
      showMessage("<html>A straight line selection is required!");
    }
  } while (selectionType != 5);
  roiManager("Add");
  px = getValue("Length");
  Dialog.create("Reference scale");
  Dialog.addNumber("Known length:", 0);
  Dialog.addChoice("Unit:", newArray("mm", "cm", "inch"));
  Dialog.show();
  num = Dialog.getNumber();
  unit = Dialog.getChoice();
  if (unit == "mm") { num = num / 10; }
  else if (unit == "inch") { num = num * 2.54; }
  pxcm = px / num;
  if (unit == "mm") { unitFactor = 10; }
  else if (unit == "inch") { unitFactor = 1 / 2.54; }
  else { unitFactor = 1; }
  roiManager("Select", roiManager("count") - 1);
  roiManager("Rename", "px.cm");
  run("Select None");
}

function getFishLength() {
  Dialog.create("Known fish length");
  Dialog.addNumber("Fish length:", 0);
  Dialog.addChoice("Unit:", newArray("mm", "cm", "inch"));
  Dialog.addChoice("Length type:", newArray("standard", "total"));
  Dialog.show();
  length = Dialog.getNumber();
  unit = Dialog.getChoice();
  lengthType = Dialog.getChoice();
  if (unit == "mm") { length = length / 10; }
  else if (unit == "inch") { length = length * 2.54; }
  if (unit == "mm") { unitFactor = 10; }
  else if (unit == "inch") { unitFactor = 1 / 2.54; }
  else { unitFactor = 1; }
}

function measureAngle(x1, y1, x2, y2) {
  dx = x2 - x1;
  dy = y2 - y1;
  a = atan2(-dy, dx) * 180 / PI;
  return a;
}

// "straightenRotate": Straighten/rotate the image if the fish is bent or tilted
var adjustment = "None";
function straightenRotate() {
  Dialog.create("Image adjustment");
  label = "The fish must be straight and horizontal.\n" +
          "Choose the action needed to adjust the image.";
  items = newArray("Straighten", "Rotate", "None");
  Dialog.addRadioButtonGroup(label, items, 3, 1, "None");
  Dialog.show();
  option = Dialog.getRadioButton();

  if (option == "Straighten") {
    do {
      run("Select None");
      setTool("Polyline");
      run("Line Width... ");
      message = "Trace a segmented line following the fish's midline.\n" +
                "The selection must span from the snout to the caudal fin.\n" +
                " \n" +
                "Adjust the selection, then, using the 'Line Width' window,\n" +
                "increase the width until the whole fish is included.\n" +
                " \n" +
                "Once satisfied, click OK.";
      waitForUser("Straighten the fish", message);
      if (selectionType != 6) {
        showMessage("<html>A segmented line selection is required!");
      }
    } while (selectionType != 6);
    run("Straighten...");
    straightened = getImageID();
    rename(title);
    selectImage(copy);
    run("Close");
    run("Line Width...", "line=1");
    if (isOpen("Line Width")) {
      selectWindow("Line Width");
      run("Close");
    }
  }
  else if (option == "Rotate") {
    do {
      run("Select None");
      setTool("Line");
      message = "Trace a straight line with the same orientation as the fish.\n" +
                "The image will be rotated by this line's angle.";
      waitForUser("Rotate the image", message);
      if (selectionType != 5) {
        showMessage("<html>A straight line selection is required!");
      }
    } while (selectionType != 5);
    getLine(x1, y1, x2, y2, lineWidth);
    rotationAngle = measureAngle(x1, y1, x2, y2);
    xmid0 = getWidth / 2;
    ymid0 = getHeight / 2;
    nROI = RoiManager.size;
    if (nROI > 0) {
      allROIs = newArray(nROI);
      for (i = 0; i < allROIs.length; i++) { allROIs[i] = i; }
      roiManager("Select", allROIs);
      RoiManager.rotate(rotationAngle, xmid0, ymid0);
    }
    run("Rotate... ", "angle=" + rotationAngle + " interpolation=Bilinear fill enlarge");
    xmid1 = getWidth / 2;
    ymid1 = getHeight / 2;
    if (nROI > 0) {
      RoiManager.translate(xmid1 - xmid0, ymid1 - ymid0);
    }
  }
  return option;
}

function roiAddRename(name) {
  roiManager("Add");
  nROI = RoiManager.size;
  roiManager("Select", (nROI - 1));
  roiManager("Rename", name);
  run("Labels...", "color=white font=8 show use draw bold");
}

// "areaXline": Intersection points between an area ROI (a) and a straight line (b)
// Adapted from: https://forum.image.sc/t/how-to-get-xy-coordinate-of-selection-line-crossing-a-roi/6923/6
function extrema(p) {
  for (i = 1; i < p.length; i++) {
    p[i-1] = abs(p[i] - p[i-1]);
  }
}
function intersection(xx, yy, s, p) {
  for (i = 0; i < 2; i++) {
    if (i > 0) { sign = -1; } else { sign = 1; }
    dx = sign * sqrt(pow(p[i], 2) / (1 + pow(s, 2)));
    xx[i] += dx;
    if (s != 1/0) { yy[i] -= s * dx; } else { yy[i] += sign * p[i]; }
  }
}
function areaXline(a, b) {
  RoiManager.selectByName(a);
  run("Create Mask");
  RoiManager.selectByName(b);
  if (selectionType != 5) {
    exit("<html>A straight line selection is required!");
  }
  getSelectionCoordinates(x, y);
  slp = -(y[0] - y[1]) / (x[0] - x[1]);
  len = sqrt(pow(x[0] - x[1], 2) + pow(y[0] - y[1], 2));
  profile = getProfile();
  extrema(profile);
  profile = Array.findMaxima(profile, 0, 1);
  for (i = 0; i < 2; i++) { profile[i] = profile[i] + 1; }
  profile[1] = len - profile[1];
  intersection(x, y, slp, profile);
  point1 = newArray(round(x[0]), round(y[0]));
  point2 = newArray(round(x[1]), round(y[1]));
  points = Array.concat(point1, point2);
  close("Mask");
  return points;
}

function dist(x1, y1, x2, y2) {
  return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
}

// "deleteRoiIfExists": removes a ROI by name, without failing if it does not
// exist. RoiManager.selectByName raises an error in that case, which would
// stop the analysis midway.
function deleteRoiIfExists(name) {
  for (j = RoiManager.size - 1; j >= 0; j--) {
    roiManager("Select", j);
    if (Roi.getName == name) {
      roiManager("Delete");
      run("Select None");
      return true;
    }
  }
  run("Select None");
  return false;
}

// Set by the input functions when the user asks to go back to the previous step.
var goBack = false;

// "manualVLine": shows a vertical line, lets the user move it, then returns its
// x-coordinate. Used for the four lines D, A, H and E.
//
// The dialog is NON-BLOCKING: an ordinary Dialog.create() would forbid touching
// the image while open, so moving the line. That is what lets a "go back"
// checkbox sit next to the adjustment.
function manualVLine(name, what, canGoBack) {
  goBack = false;
  makeLine(xmid, 0, xmid, h);
  roiAddRename(name);
  do {
    Dialog.createNonBlocking("Reference line " + name);
    Dialog.addMessage("LINE " + name + "\n \n" + what);
    Dialog.addMessage("Drag the line left or right,\n" +
                      "then click OK.");
    if (canGoBack) {
      Dialog.addCheckbox("<<  Go back to the previous line", false);
    }
    Dialog.show();
    if (canGoBack) {
      goBack = Dialog.getCheckbox();
      if (goBack) {
        deleteRoiIfExists(name);
        return -1;
      }
    }
    ok = (selectionType == 5);
    if (!ok) {
      showMessage("<html>Line " + name + " is no longer selected.<br>"
                + "Redraw a vertical line at the desired position.");
    }
  } while (!ok);
  getSelectionCoordinates(vx, vy);
  // The line may have been redrawn at an angle: keep only the x-coordinate
  deleteRoiIfExists(name);
  makeLine(vx[0], 0, vx[0], h);
  roiAddRename(name);
  return vx[0];
}

// "checkLineOrder": checks that D, A, H and E follow in order from snout to
// tail. An inversion almost always means an orientation error, and would give
// negative or absurd lengths without notice.
function checkLineOrder(side, xD, xA, xH, xE) {
  if (side == "left") {
    ok = (xD < xA) && (xA <= xH) && (xH < xE);
  } else {
    ok = (xD > xA) && (xA >= xH) && (xH > xE);
  }
  if (!ok) {
    showMessage("<html>Inconsistent line order!<br><br>" +
      "Expected from snout to tail: D, A, H, E.<br>" +
      "Check the chosen orientation (" + side + ") and the line placement.<br><br>" +
      "The analysis continues, but the measurements should be checked.");
  }
}

// "traitLine": draws the measurement as a named ROI and returns its length in pixels.
// Each trait is thus kept in the RoiSet and can be reviewed on the image.
function traitLine(name, x1, y1, x2, y2) {
  makeLine(x1, y1, x2, y2);
  roiAddRename(name);
  return getValue("Length");
}

// "traitLineLM": same, but between two landmarks designated by their code
function traitLineLM(name, code1, code2) {
  return traitLine(name, getLMx(code1), getLMy(code1), getLMx(code2), getLMy(code2));
}

//--------------------------  RESULTS FORMATTING  ---------------------------------------//

// Measurements are output in the UNIT entered for the scale (mm, cm or inch),
// exactly like ImageJ: value = pixels / px.cm * factor (mm=10, cm=1, inch=1/2.54).
// Without a scale (px.cm == "NA"), the values stay in raw pixels.
// The px.cm scale factor (pixels per cm) is written in its own column.
// The conversion is done on NUMBERS (not via a string-returning function), which
// avoids the "Numeric return value expected" error of the comma formatting.

//--------------------  MEASUREMENTS: ALWAYS COMPUTED (MetricFishJ)  ---------------------//

// Every landmark is ALWAYS placed during digitizing (at an assumed position if
// needed), so every measurement always yields a value: no cell is left empty,
// whatever the placement quality. The functions keep their original signatures
// (the "required" codes reqA/reqB are kept but ignored) so the 44 measurement
// call sites are unchanged.
function lmOK(code) {
  return true;   // kept for compatibility: every landmark is deemed placed
}
// Direct distance between 2 landmarks.
function mLM(name, c1, c2) {
  return traitLineLM(name, c1, c2);
}
// Horizontal projection at level y, from x1 to x2.
function mHproj(name, x1, x2, y, reqA, reqB) {
  return traitLine(name, x1, y, x2, y);
}
// Vertical distance (Y gap) between 2 landmarks, drawn at abscissa xDraw.
function mVert(name, xDraw, cTop, cBot) {
  return traitLine(name, xDraw, getLMy(cTop), xDraw, getLMy(cBot));
}

//---------------------------  BATCH ANALYSIS FUNCTIONS  ----------------------------------//

var inputDir = "", outputDir1 = "", outputDir2 = "";
var fileName = "", fileExt = "", filePath = "";
var logFile = "";
var newList = "";

// Discard anything that isn't a photo: required when the output folder
// (results/log/ROI .zip) is the same as the input folder - getFileList()
// would then also return those output files, and open() on them opens a
// TEXT window (not an image), crashing duplicateImage() further down for
// lack of an active image ("No Image").
function isImageFile(name) {
  lower = toLowerCase(name);
  if (endsWith(lower, "/")) return false;   // subfolder
  exts = newArray(".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp");
  for (e = 0; e < exts.length; e++) {
    if (endsWith(lower, exts[e])) return true;
  }
  return false;
}

function setupMultiAnalysis() {
  Dialog.create("Folders and results file name/format");
  Dialog.addDirectory("Input folder", "");
  Dialog.addDirectory("ROI output folder", "");
  Dialog.addDirectory("Results output folder", "");
  Dialog.addString("Results file name", "MetricFishJ_Traits");
  // .xls and .txt are both tab-separated: Excel opens the .xls directly in
  // columns, the .txt opens anywhere. No .csv (the semicolon Excel expects in
  // a French locale breaks opening a comma-separated csv).
  Dialog.addChoice("File format", newArray(".txt", ".xls"));
  Dialog.show();
  inputDir = Dialog.getString();
  outputDir1 = Dialog.getString();
  outputDir2 = Dialog.getString();
  fileName = Dialog.getString();
  fileExt = Dialog.getChoice();

  getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
  sep = "_";
  month = month + 1;
  if (month < 10) { month = "0" + month; }
  if (dayOfMonth < 10) { dayOfMonth = "0" + dayOfMonth; } else { dayOfMonth = d2s(dayOfMonth, 0); }
  date = dayOfMonth + sep + month + sep + year;

  checkInput = File.isDirectory(inputDir);
  checkOutput1 = File.isDirectory(outputDir1);
  checkOutput2 = File.isDirectory(outputDir2);

  if ((checkInput && checkOutput1 && checkOutput2) == 1) {
    fileListOut = getFileList(outputDir2);
    if (fileListOut.length != 0) {
      for (i = 0; i < fileListOut.length; i++) {
        if (fileListOut[i].startsWith("TraitLog")) {
          exit("<html><center><b>WARNING!</b><br>"
             + "A <i>TraitLog</i> file already exists in the output folder.<br>"
             + "Delete it manually if you are sure you no longer need it.</center>");
        }
      }
    }
    allFiles = getFileList(inputDir);
    newList = newArray(0);
    for (fi = 0; fi < allFiles.length; fi++) {
      if (isImageFile(allFiles[fi])) newList = Array.concat(newList, allFiles[fi]);
    }
    logFile = outputDir2 + "TraitLog_" + date + ".txt";
    f = File.open(logFile);
    print(f, "Input_directory: " + inputDir);
    print(f, "Output_ROIs: " + outputDir1);
    print(f, "Output_results: " + outputDir2);
    print(f, "File_name: " + fileName);
    print(f, "File_extension: " + fileExt);
    print(f, "Date: " + date);
    File.close(f);

    filePath = outputDir2 + fileName + fileExt;
    res = File.open(filePath);
    print(res, colnames());
    File.close(res);
  } else {
    exit("<html><center><b>WARNING!</b><br>Not all folders have been selected</center>");
  }
}

// The 44 traits, in the order of the specification (1 -> 44), computed from the
// 33 landmarks and the A-H reference lines. The 10 added traits (eye:
// LprO, LpsO, Mu, DO, DSO; head: Hte, HM; spines: L2EA, E2EA, L3EA, L4ED) rely on
// landmarks 23 to 33. With selection-before-placement, only the points of ticked
// traits are requested (at an assumed position if needed); unticked traits still
// compute a value from (0,0)-default points but are never shown or exported
// (filtered out by isSelected()/selectedSubset()).
var traitCodes = newArray(
  "TL","SL","LprA","LbA","LprPl","LbPl","LPl","LprPc","LbPc","LPc",
  "LprD","LbD","LbDE","LbDM","HL","LEJ","LprO","LpsO","Mu","DO",
  "DSO","Hte","HM","H","DDEPl","DDEPc","DDEA","DDMPl","DDMPc","DDMA","DPcPl",
  "DPcA","DPlA","HPC","LPC1","LPC2","LC","HC","L1EA","L2EA","E2EA",
  "L3EA","LEPl","L4ED",
  "LprD2","LbD2","DD1D2","LBarb","LbAd","LMax","HD","HA",
  "L2D","LEPc","L1ED","L2ED","L3ED");

// v2.4.1: selection of measurements to compute (checkboxes, right after the ID).
var traitSel = newArray(0);
function isSelected(k) {
  if (traitSel.length != traitCodes.length) return true;
  return traitSel[k];
}
function selectedSubset(arr) {
  out = newArray(0);
  for (k = 0; k < arr.length; k++) {
    if (isSelected(k)) out = Array.concat(out, arr[k]);
  }
  return out;
}
function askTraitSelection() {
  defs = newArray(traitCodes.length);
  for (k = 0; k < traitCodes.length; k++) defs[k] = (k < 44);   // group A unticked by default
  Dialog.create("Select measurements");
  Dialog.addMessage("Tick the measurements to obtain (default: all).\nCode meanings: manual, section 9.");
  Dialog.addCheckboxGroup(15, 4, traitCodes, defs);
  Dialog.show();
  traitSel = newArray(traitCodes.length);
  for (k = 0; k < traitCodes.length; k++) traitSel[k] = Dialog.getCheckbox();
}

function colnames() {
  sep = "\t";   // .xls like .txt: columns separated by tab
  str = newArray("Image_id", "px.cm");
  str = Array.concat(str, selectedSubset(traitCodes));
  str = Array.concat(str, newArray("remark", "time"));
  str = String.join(str, sep);
  return str;
}

function saveResults() {
  sep = "\t";
  // Measurements converted to the entered scale unit (mm/cm/inch) via ImageJ's conversion:
  // pixels / px.cm. Without a scale (px.cm == "NA"), raw pixels are kept.
  vals = newArray(traitValues.length);
  for (m = 0; m < traitValues.length; m++) {
    // An unticked Group A measurement leaves traitValues[m] as "" (empty
    // string, never placed), not a number: dividing "" by pxcm crashes the
    // interpreter. Skip the conversion (setMorphoTable already does this) -
    // the value would be dropped anyway by selectedSubset below.
    if (!isSelected(m)) continue;
    tv = traitValues[m];
    if (pxcm != "NA") {
      conv = tv / pxcm;
      conv = conv * unitFactor;
    } else {
      conv = tv;
    }
    vals[m] = conv;
  }
  str = newArray(title, pxcm);
  str = Array.concat(str, selectedSubset(vals));
  str = Array.concat(str, newArray(remark, time));
  str = String.join(str, sep);
  File.append(str, filePath);
}

function saveAdjustedImages(adjustment) {
  if (adjustment == "Straighten") {
    saveAs("Jpeg", outputDir1 + title + "_straightened");
  } else if (adjustment == "Rotate") {
    saveAs("Jpeg", outputDir1 + title + "_rotated");
  }
}

//----------------------------  LANDMARKS (clicked points)  ------------------------------//

// The landmarks, in the order and at the positions of the reference figure.
// They are placed one by one, tpsDig style: each landmark is homologous and
// sits on the outline or on a sharp anatomical junction, which makes them
// repeatable across individuals. They feed the 44 measurements and are kept in
// the RoiSet.
// Landmarks 1 to 14 keep the numbering of the reference figure; 15 and 16
// are swapped (pelvPost then pelvOrigin) to group the 2 pelvic-fin
// landmarks together and make them easier to place one after the other.
// Landmarks 17 to 22 complete the pectoral, pelvic and anal fins.
// Landmarks 23 to 33 add the eye and the spines (4th dorsal, 2nd/3rd anal).
// Redundant landmarks removed (skullTop, headVentEye, headVentSnout) -> 33 landmarks.
// Head measures: Hte = pt 7 -> pt 3 (direct); DSO = pt 25 -> line C;
// HM = pt 5 -> line C (verticals). -> 44 measurements.
var lmCodes = newArray(
  "opercDors",     // 1
  "opercPost",     // 2
  "isthmus",       // 3
  "jawLower",      // 4
  "snoutTip",      // 5
  "headDors",      // 6
  "nape",          // 7
  "dorsOrigin",    // 8
  "dorsJunction",  // 9
  "dorsEnd",       // 10
  "pedDors",       // 11
  "pedVent",       // 12
  "analEnd",       // 13
  "analOrigin",    // 14
  "pelvPost",      // 15
  "pelvOrigin",    // 16
  "pecOrigin",     // 17
  "pecSup",        // 18
  "pecTip",        // 19
  "pelvSpineTip",  // 20
  "pelvTip",       // 21
  "analSpine1Tip", // 22
  "eyeAnt",        // 23
  "eyePost",       // 24
  "eyeVent",       // 25
  "dorsSpine4Base",// 26
  "dorsSpine4Tip", // 27
  "analSpine2Base",// 28
  "analSpine2Tip", // 29
  "analSpine2Low", // 30
  "analSpine2Up",  // 31
  "analSpine3Base",// 32
  "analSpine3Tip", // 33
  "dors2Origin",   // 34  (group A)
  "dors2End",      // 35
  "barbelBase",    // 36
  "barbelTip",     // 37
  "adiposeOrigin", // 38
  "adiposeEnd",    // 39
  "maxillaEnd",    // 40
  "dorsRayTip",    // 41
  "analRayTip",    // 42
  "dors2RayTip",   // 43  (group A)
  "pecSpineTip",   // 44
  "dorsSpine1Base",// 45
  "dorsSpine1Tip", // 46
  "dorsSpine2Base",// 47
  "dorsSpine2Tip", // 48
  "dorsSpine3Base",// 49
  "dorsSpine3Tip");// 50

var lmPrompts = newArray(
  "1/33 - DORSAL margin of the operculum (origin of the lateral line).",
  "2/33 - POSTERIOR margin of the operculum (tip of the skin flap).",
  "3/33 - Isthmus: median junction of the opercula, under the throat.",
  "4/33 - POSTERIOR tip of the lower jaw (mouth corner).",
  "5/33 - ANTERIOR tip of the snout (tip of the upper jaw).",
  "6/33 - DORSAL head profile, vertically above the posterior eye margin.",
  "7/33 - Nape: dorsal profile, midway between point 6 and the dorsal fin.",
  "8/33 - Dorsal fin origin (base of the 1st spine).",
  "9/33 - SPINY / SOFT dorsal junction (base of the last spine).",
  "10/33 - End of the dorsal fin base (last soft ray).",
  "11/33 - DORSAL insertion of the caudal fin (top of the peduncle).",
  "12/33 - VENTRAL insertion of the caudal fin (bottom of the peduncle).",
  "13/33 - End of the anal fin base (last ray).",
  "14/33 - Anal fin origin (base of the 1st spine).",
  "15/33 - PELVIC: POSTERIOR insertion (end of the base).",
  "16/33 - Pelvic fin origin (anterior insertion).",
  "17/33 - Pectoral fin origin: LOWER insertion of the base.",
  "18/33 - PECTORAL: UPPER insertion of the base.",
  "19/33 - PECTORAL: distal tip of the longest ray.",
  "20/33 - PELVIC: distal tip of the SPINE.",
  "21/33 - PELVIC: distal tip of the longest soft ray.",
  "22/33 - ANAL: distal tip of the 1st SPINE.",
  "23/33 - ANTERIOR margin of the eye.",
  "24/33 - POSTERIOR margin of the eye.",
  "25/33 - LOWER (ventral) margin of the eye.",
  "26/33 - Base of the 4th DORSAL SPINE.",
  "27/33 - Distal tip of the 4th DORSAL SPINE.",
  "28/33 - Base of the 2nd ANAL SPINE.",
  "29/33 - Distal tip of the 2nd ANAL SPINE.",
  "30/33 - LOWER edge of the 2nd anal spine (for thickness).",
  "31/33 - UPPER edge of the 2nd anal spine (for thickness).",
  "32/33 - Base of the 3rd ANAL SPINE.",
  "33/33 - Distal tip of the 3rd ANAL SPINE.",
  "Group A - Origin of the 2nd DORSAL fin.",
  "Group A - End of the 2nd DORSAL fin base.",
  "Group A - Base of the BARBEL (on the lip / snout).",
  "Group A - Tip of the BARBEL.",
  "Group A - Origin of the ADIPOSE fin.",
  "Group A - End of the ADIPOSE fin base.",
  "Group A - POSTERIOR end of the MAXILLA (upper jaw).",
  "Group A - Tip of the longest DORSAL fin ray.",
  "Group A - Tip of the longest ANAL fin ray.",
  "Group A - Tip of the longest 2nd DORSAL fin ray.",
  "Group A - Tip of the PECTORAL SPINE.",
  "Group A - Base of the 1st DORSAL SPINE.",
  "Group A - Distal tip of the 1st DORSAL SPINE.",
  "Group A - Base of the 2nd DORSAL SPINE.",
  "Group A - Distal tip of the 2nd DORSAL SPINE.",
  "Group A - Base of the 3rd DORSAL SPINE.",
  "Group A - Distal tip of the 3rd DORSAL SPINE.");

var LMx = newArray(0), LMy = newArray(0);
// LMok[i] becomes 1 when point i is placed (all are: no more "absent").
var LMok = newArray(0);
// History of points actually placed, in chronological order (not lmCodes order:
// measure groups are requested conditionally). Used by the "go back to the
// previous point" checkbox in placeOnePoint.
var placeHistory = newArray(0);

// "digitizeLandmarks": records the points one by one.
//
// From the 2nd point on, a "go back to the previous point" checkbox lets you
// fix a missed click without redoing everything: the previous point is removed
// from the ROI Manager and asked again. You can walk back as many points as you
// like, down to the first.
//
// The dialog is NON-BLOCKING, otherwise ImageJ would refuse the click on the image.
// v1: ALL landmarks (base and group A) are placed only if a ticked measure
// needs them - see placeBaseLandmarks/placeOptionalLandmarks.
function lmPlaced(code) { return LMok[getLMindex(code)] == 1; }
function isSelectedByCode(code) {
  for (t = 0; t < traitCodes.length; t++) {
    if (traitCodes[t] == code) return isSelected(t);
  }
  return false;
}
function placeOnePoint(idx) {
  // ITERATIVE, not recursive (unlike an earlier version): "current" moves
  // forward/backward inside a single loop, never calling placeOnePoint from
  // within itself - same pattern manualVLine already uses for lines D/A/H/E.
  // We only exit once the original idx has actually been placed, even after
  // several back-and-forths.
  var current, done, canBack, prevIdx, back;
  current = idx;
  done = false;
  while (!done) {
    run("Select None");
    setTool("Point");
    Dialog.createNonBlocking("Point: " + lmCodes[current]);
    Dialog.addMessage(lmPrompts[current]);
    Dialog.addMessage("Click the point (assumed position accepted), then OK.");
    canBack = 0;
    if (placeHistory.length > 0) canBack = 1;
    if (canBack) {
      prevIdx = placeHistory[placeHistory.length - 1];
      Dialog.addCheckbox("<<  Go back to the previous point (" + lmCodes[prevIdx] + ")", false);
    }
    Dialog.show();
    back = false;
    if (canBack) back = Dialog.getCheckbox();
    if (back) {
      prevIdx = placeHistory[placeHistory.length - 1];
      placeHistory = Array.trim(placeHistory, placeHistory.length - 1);
      deleteRoiIfExists(lmCodes[prevIdx]);
      LMok[prevIdx] = 0;
      current = prevIdx;   // redo that point, within the same loop
    } else if (selectionType == 10) {
      getSelectionCoordinates(x, y);
      LMx[current] = x[0]; LMy[current] = y[0]; LMok[current] = 1;
      roiAddRename(lmCodes[current]);
      placeHistory = Array.concat(placeHistory, current);
      if (current == idx) {
        done = true;
      } else {
        current = idx;   // previous point fixed: go back to ask for idx
      }
    } else {
      showMessage("<html>Point selection required! Click on the image.");
    }
  }
}
function ensureLm(code, lms) {
  if (!isSelectedByCode(code)) return;
  for (m = 0; m < lms.length; m++) {
    if (LMok[getLMindex(lms[m])] != 1) placeOnePoint(getLMindex(lms[m]));
  }
}
// Checks if the 44 BASE traits are selected (indices 0-43)
// Group A (indices 44-56) is optional
function allBaseTraitsSelected() {
  for (k = 0; k < 44; k++) {  // only check the 44 base traits
    if (!traitSel[k]) return false;
  }
  return true;
}

// Places the 33 BASE landmarks in sequential order (1 to 33), useful when all
// base traits are selected for optimal user experience. Deliberately capped at
// index 33 (the first 33 elements of lmCodes): Group A landmarks (33-49) stay
// handled by placeOptionalLandmarks, which filters them one by one against the
// Group A traits actually ticked - otherwise EVERY optional landmark would be
// requested as soon as the 44 base traits are selected, even with no Group A
// trait ticked at all.
function placeSequentialLandmarks() {
  for (idx = 0; idx < 33; idx++) {
    if (!lmPlaced(lmCodes[idx])) {
      placeOnePoint(idx);
    }
  }
}

function placeOptionalLandmarks() {
  ensureLm("LprD2", newArray("dors2Origin"));
  ensureLm("LbD2",  newArray("dors2Origin", "dors2End"));
  ensureLm("DD1D2", newArray("dors2Origin"));
  ensureLm("LBarb", newArray("barbelBase", "barbelTip"));
  ensureLm("LbAd",  newArray("adiposeOrigin", "adiposeEnd"));
  ensureLm("LMax",  newArray("maxillaEnd"));
  ensureLm("HD",    newArray("dorsRayTip"));
  ensureLm("HA",    newArray("analRayTip"));
  ensureLm("L2D",   newArray("dors2Origin", "dors2RayTip"));
  ensureLm("LEPc",  newArray("pecSpineTip"));
  ensureLm("L1ED",  newArray("dorsSpine1Base", "dorsSpine1Tip"));
  ensureLm("L2ED",  newArray("dorsSpine2Base", "dorsSpine2Tip"));
  ensureLm("L3ED",  newArray("dorsSpine3Base", "dorsSpine3Tip"));
}

// v1: the 44 base measurements also each have their required points - only
// those needed by at least one ticked measurement are requested. TL, SL, LC,
// HPC and HC don't depend on any point (only on lines D/A/H/E and the outline,
// always placed), so they don't appear below.
function placeBaseLandmarks() {
  ensureLm("LprA",  newArray("analOrigin"));
  ensureLm("LprPl", newArray("pelvOrigin"));
  ensureLm("LprPc", newArray("pecOrigin"));
  ensureLm("LprD",  newArray("dorsOrigin"));
  ensureLm("HL",    newArray("opercPost"));
  ensureLm("LEJ",   newArray("isthmus"));
  ensureLm("LPC1",  newArray("dorsEnd", "pedDors"));
  ensureLm("LPC2",  newArray("analEnd", "pedVent"));
  ensureLm("LbA",   newArray("analOrigin", "analEnd"));
  ensureLm("LbD",   newArray("dorsOrigin", "dorsEnd"));
  ensureLm("LbDE",  newArray("dorsOrigin", "dorsJunction"));
  ensureLm("LbDM",  newArray("dorsJunction", "dorsEnd"));
  ensureLm("LbPc",  newArray("pecSup", "pecOrigin"));
  ensureLm("LPc",   newArray("pecSup", "pecTip"));
  ensureLm("LbPl",  newArray("pelvOrigin", "pelvPost"));
  ensureLm("LPl",   newArray("pelvOrigin", "pelvTip"));
  ensureLm("LEPl",  newArray("pelvOrigin", "pelvSpineTip"));
  ensureLm("L1EA",  newArray("analOrigin", "analSpine1Tip"));
  ensureLm("H",     newArray("dorsOrigin"));
  ensureLm("DDEPl", newArray("dorsOrigin", "pelvOrigin"));
  ensureLm("DDEPc", newArray("dorsOrigin", "pecOrigin"));
  ensureLm("DDEA",  newArray("dorsOrigin", "analOrigin"));
  ensureLm("DDMPl", newArray("dorsJunction", "pelvOrigin"));
  ensureLm("DDMPc", newArray("dorsJunction", "pecOrigin"));
  ensureLm("DDMA",  newArray("dorsJunction", "analOrigin"));
  ensureLm("DPcPl", newArray("pecOrigin", "pelvOrigin"));
  ensureLm("DPcA",  newArray("pecOrigin", "analOrigin"));
  ensureLm("DPlA",  newArray("pelvOrigin", "analOrigin"));
  ensureLm("LprO",  newArray("eyeAnt"));
  ensureLm("LpsO",  newArray("eyePost", "opercPost"));
  ensureLm("Mu",    newArray("snoutTip", "jawLower"));
  ensureLm("DO",    newArray("eyeAnt", "eyePost"));
  ensureLm("DSO",   newArray("eyeVent"));
  ensureLm("Hte",   newArray("nape", "isthmus"));
  ensureLm("HM",    newArray("snoutTip"));
  ensureLm("L2EA",  newArray("analSpine2Base", "analSpine2Tip"));
  ensureLm("E2EA",  newArray("analSpine2Low", "analSpine2Up"));
  ensureLm("L3EA",  newArray("analSpine3Base", "analSpine3Tip"));
  ensureLm("L4ED",  newArray("dorsSpine4Base", "dorsSpine4Tip"));
}

function digitizeLandmarks() {
  // If resuming AND landmarks had already started (LMok already the right
  // size), keep arrays (preserve already-placed points). If resuming from an
  // EARLIER step (e.g. lines), LMok is still empty (newArray(0)): it must
  // still be initialized normally, otherwise LMok[...] crashes with
  // "Empty array".
  if (!resuming || LMok.length != lmCodes.length) {
    LMx = newArray(lmCodes.length);
    LMy = newArray(lmCodes.length);
    LMok = newArray(lmCodes.length);   // 0 by default; set to 1 when placed
  }
  run("Point Tool...", "type=Dot color=Red size=Medium");

  // If all 44 BASE traits are selected, place the 33 base landmarks in
  // sequential order; otherwise place only the base landmarks required by the
  // selected base traits (optimized order). Either way, Group A landmarks
  // (2nd dorsal, barbel, adipose...) stay individually filtered by
  // placeOptionalLandmarks against the Group A traits actually ticked.
  if (!landmarks_done) {
    if (allBaseTraitsSelected()) {
      placeSequentialLandmarks();
    } else {
      placeBaseLandmarks();
    }
    landmarks_done = true;
  }

  if (!optional_done) {
    placeOptionalLandmarks();
    optional_done = true;
  }
}

function getLMindex(code) {
  for (j = 0; j < lmCodes.length; j++) {
    if (lmCodes[j] == code) return j;
  }
  exit("Reference landmark not found: " + code);
}
function getLMx(code) { return LMx[getLMindex(code)]; }
function getLMy(code) { return LMy[getLMindex(code)]; }

//------------------------------  MAIN ANALYSIS  ------------------------------------------//

var title = "", titleWithExt = "", time = "", remark = "";
var traitValues = newArray(0);

function morphoAnalysis() {

  t0 = getTime;

  // Remove any scale carried by the image metadata:
  // all measurements are in pixels, "px.cm" gives the conversion factor.
  run("Set Scale...", "distance=0 known=0 unit=pixel");

  // Scale
  getScale();

  // Image adjustment if the fish is bent or tilted
  adjustment = straightenRotate();

  // Image size
  getImageSize();

  // Orientation
  side = getOrientation();


  // AUTOMATIC REFERENCE LINES (B to G), derived from the body outline //

  // Fish outline, with confirmation before validating.
  //
  // Everything else (lines B, C, F, G, and HPC) depends on this outline: an
  // error here (bitten end, wrong side) would often only show at measurement
  // time. So we show the smoothed outline and ask for confirmation before
  // freezing it, with the option to redraw it in place.
  do {
    do {
      run("Select None");
      setTool("Polygon");
      message = "Trace a polygon following the body outline, including\n" +
              "the caudal fin, but WITHOUT the dorsal, pelvic and anal fins.\n" +
              " \n" +
              "If the pectoral fin extends past the body, follow the\n" +
              "imagined body outline beneath the fin.";
      waitForUser("Fish outline", message);
      if (selectionType != 2) {
        showMessage("<html>A polygon selection is required!");
      }
    } while (selectionType != 2);
    run("Interpolate", "interval=1 smooth adjust");
    run("Fit Spline");

    Dialog.createNonBlocking("Confirm the outline");
    Dialog.addMessage("FISH OUTLINE\n \n" +
                      "The smoothed outline is shown on the image. Check that it\n" +
                      "follows the body and caudal fin correctly, without cutting\n" +
                      "into the dorsal, pelvic or anal fin, then click OK.");
    Dialog.addCheckbox("No, redraw the outline", false);
    Dialog.show();
    redoOutline = Dialog.getCheckbox();
  } while (redoOutline);
  roiAddRename("outline");
  outlineroi = RoiManager.size - 1;

  // MANUALLY PLACED VERTICAL LINES: D, A, H, E //
  // They are requested in anterior -> posterior order.
  // B, C, F and G stay derived from the outline (see below).
  // From the second on, you can go back to the previous one to fix it.

  lineHelp = newArray(
    "Vertical line tangent to the most ANTERIOR tip of the body\n" +
    "(tip of the snout, upper jaw closed).",

    "Vertical line at the NARROWEST point of the caudal peduncle.\n" +
    " \n" +
    "It also separates the body from the caudal fin: the automatic\n" +
    "lines B, C, F and G all depend on it.",

    "Vertical line where the caudal fin rays begin\n" +
    "(end of the caudal peduncle).\n" +
    " \n" +
    "It marks the end of the standard length.",

    "Vertical line tangent to the most POSTERIOR tip of the\n" +
    "caudal fin (tip of the longest lobe).");

  if (!lines_done) {
    lineX = newArray(4);
    k = 0;
    while (k < 4) {
      // ImageJ refuses a comparison (k > 0) directly as an argument:
      // precompute it into a variable.
      canBack = 0;
      if (k > 0) canBack = 1;
      r = manualVLine(lineNames[k], lineHelp[k], canBack);
      if (goBack) {
        k = k - 1;
        deleteRoiIfExists(lineNames[k]);   // it will be redrawn next round
      } else {
        lineX[k] = r;
        k = k + 1;
      }
    }
    lines_done = true;
  }
  xD = lineX[0];
  xA = newArray(lineX[1], lineX[1]);
  xH = lineX[2];
  xE = lineX[3];

  checkLineOrder(side, xD, xA[0], xH, xE);

  setBatchMode(true);

  if (!derived_done) {
  // Intersection points along A (used for HPC)
  APoints = areaXline("outline", "A");

  // Split body (Bs) and caudal fin (CFs) at line A
  if (side == "left") {
    makeRectangle(0, 0, xA[0], h);
    roiManager("Add");
    rect1roi = RoiManager.size - 1;
    roiManager("Select", newArray(outlineroi, rect1roi));
    roiManager("AND");
    roiAddRename("Bs");
    makeRectangle(xA[0], 0, w, h);
    roiManager("Add");
    rect2roi = RoiManager.size - 1;
    roiManager("Select", newArray(outlineroi, rect2roi));
    roiManager("AND");
    roiAddRename("CFs");
    roiManager("Select", newArray(rect1roi, rect2roi));
    roiManager("Delete");
  } else {
    makeRectangle(xA[0], 0, w, h);
    roiManager("Add");
    rect1roi = RoiManager.size - 1;
    roiManager("Select", newArray(outlineroi, rect1roi));
    roiManager("AND");
    roiAddRename("Bs");
    makeRectangle(0, 0, xA[0], h);
    roiManager("Add");
    rect2roi = RoiManager.size - 1;
    roiManager("Select", newArray(outlineroi, rect2roi));
    roiManager("AND");
    roiAddRename("CFs");
    roiManager("Select", newArray(rect1roi, rect2roi));
    roiManager("Delete");
  }

  // HORIZONTAL LINES DERIVED FROM THE OUTLINE (B, C, F, G) //

  // Bounding box of the body (Bs) -> B and C
  RoiManager.selectByName("Bs");
  yB = getValue("BY");
  yC = yB + getValue("Height");
  // Line B - highest dorsal edge of the body (fins excluded)
  makeLine(0, yB, w, yB);
  roiAddRename("B");
  // Line C - lowest ventral edge of the body (fins excluded)
  makeLine(0, yC, w, yC);
  roiAddRename("C");

  // Bounding box of the caudal fin (CFs) -> F and G
  RoiManager.selectByName("CFs");
  yF = getValue("BY");
  yG = yF + getValue("Height");
  // Line F - highest edge of the caudal fin
  if (side == "left") {
    makeLine(xA[0], yF, w, yF);
  } else {
    makeLine(0, yF, xA[0], yF);
  }
  roiAddRename("F");
  // Line G - lowest edge of the caudal fin
  if (side == "left") {
    makeLine(xA[0], yG, w, yG);
  } else {
    makeLine(0, yG, xA[0], yG);
  }
  roiAddRename("G");
  derived_done = true;
  }

  setBatchMode(false);


  // LANDMARKS (only those required by ticked measurements are requested) //
  digitizeLandmarks();


  // COMPUTE THE 52 MEASUREMENTS //

  setBatchMode(true);

  // All measurements are computed from the placed points: mLM = direct distance
  // (2 points), mHproj = horizontal projection, mVert = vertical gap. Every trait
  // always receives a value (no empty cell).

  // -- Axial lengths (horizontal projections) --
  TL    = traitLine("TL", xD, yC, xE, yC);
  SL    = traitLine("SL", xD, yB, xH, yB);
  LprA  = mHproj("LprA", xD, getLMx("analOrigin"), yC, "analOrigin", "");
  LprPl = mHproj("LprPl", xD, getLMx("pelvOrigin"), yC, "pelvOrigin", "");
  LprPc = mHproj("LprPc", xD, getLMx("pecOrigin"), yC, "pecOrigin", "");
  LprD  = mHproj("LprD", xD, getLMx("dorsOrigin"), yB, "dorsOrigin", "");
  HL    = mHproj("HL", xD, getLMx("opercPost"), yC, "opercPost", "");
  LEJ   = mHproj("LEJ", xD, getLMx("isthmus"), yC, "isthmus", "");
  // LPC1/LPC2: caudal peduncle length, DIRECT distances (dorsal edge
  // 10->11 dorsEnd->pedDors; ventral edge 13->12 analEnd->pedVent).
  LPC1  = mLM("LPC1", "dorsEnd", "pedDors");
  LPC2  = mLM("LPC2", "analEnd", "pedVent");
  LC    = traitLine("LC", xH, yC, xE, yC);

  // -- Base, ray and spine lengths (direct distances) --
  LbA   = mLM("LbA", "analOrigin", "analEnd");
  LbD   = mLM("LbD", "dorsOrigin", "dorsEnd");
  LbDE  = mLM("LbDE", "dorsOrigin", "dorsJunction");
  LbDM  = mLM("LbDM", "dorsJunction", "dorsEnd");
  LbPc  = mLM("LbPc", "pecSup", "pecOrigin");
  LPc   = mLM("LPc", "pecSup", "pecTip");
  LbPl  = mLM("LbPl", "pelvOrigin", "pelvPost");
  LPl   = mLM("LPl", "pelvOrigin", "pelvTip");
  LEPl  = mLM("LEPl", "pelvOrigin", "pelvSpineTip");
  L1EA  = mLM("L1EA", "analOrigin", "analSpine1Tip");

  // -- Heights derived from the reference lines --
  // H: max body depth (lines B and C), at mid-body; depends on dorsOrigin.
  bodyH = "";
  if (lmOK("dorsOrigin")) {
    xMBd  = getLMx("dorsOrigin") + ((xA[0] - getLMx("dorsOrigin")) / 2);
    bodyH = traitLine("H_corps", xMBd, yB, xMBd, yC);
  }
  // HPC: min caudal peduncle depth (line A x outline) -> never blank.
  HPC   = traitLine("HPC", APoints[0], APoints[1], APoints[2], APoints[3]);
  // HC: caudal fin height (lines F and G) -> never blank.
  HC    = traitLine("HC", xE, yF, xE, yG);

  // -- Inter-fin distances (direct distances) --
  DDEPl = mLM("DDEPl", "dorsOrigin", "pelvOrigin");
  DDEPc = mLM("DDEPc", "dorsOrigin", "pecOrigin");
  DDEA  = mLM("DDEA", "dorsOrigin", "analOrigin");
  DDMPl = mLM("DDMPl", "dorsJunction", "pelvOrigin");
  DDMPc = mLM("DDMPc", "dorsJunction", "pecOrigin");
  DDMA  = mLM("DDMA", "dorsJunction", "analOrigin");
  DPcPl = mLM("DPcPl", "pecOrigin", "pelvOrigin");
  DPcA  = mLM("DPcA", "pecOrigin", "analOrigin");
  DPlA  = mLM("DPlA", "pelvOrigin", "analOrigin");

  // pxcm if fish length is known instead of a reference object
  if (length != "NA") {
    if (lengthType == "standard") {
      pxcm = SL / length;
    } else if (lengthType == "total") {
      pxcm = TL / length;
    }
  }

  // -- Eye / head measurements (17-22) --
  LprO = mHproj("LprO", xD, getLMx("eyeAnt"), yC, "eyeAnt", "");
  LpsO = mHproj("LpsO", getLMx("eyePost"), getLMx("opercPost"), yC, "eyePost", "opercPost");
  Mu   = mLM("Mu", "snoutTip", "jawLower");
  DO   = mLM("DO", "eyeAnt", "eyePost");
  // DSO: suborbital distance, VERTICAL drop from point 25 (eyeVent) down to
  // line C (horizontal belly line).
  xDSO = getLMx("eyeVent");
  DSO  = traitLine("DSO", xDSO, getLMy("eyeVent"), xDSO, yC);
  // Hte: head height, DIRECT distance point 7 (nape) -> point 3 (isthmus).
  Hte  = mLM("Hte", "nape", "isthmus");
  // HM: snout height, VERTICAL drop from point 5 (snoutTip) -> line C.
  xHM  = getLMx("snoutTip");
  HM   = traitLine("HM", xHM, getLMy("snoutTip"), xHM, yC);

  // -- 2nd/3rd anal spines and 4th dorsal spine (40-44) --
  L2EA = mLM("L2EA", "analSpine2Base", "analSpine2Tip");
  // E2EA = thickness: DIRECT distance (horizontal/diagonal) between the two
  // edges (lower and upper) of the 2nd anal spine.
  E2EA = mLM("E2EA", "analSpine2Low", "analSpine2Up");
  L3EA = mLM("L3EA", "analSpine3Base", "analSpine3Tip");
  // L4ED = direct distance base -> tip, like L1EA/L2EA/L3EA.
  L4ED = mLM("L4ED", "dorsSpine4Base", "dorsSpine4Tip");

  // -- v1: optional measurements (group A), computed only if placed --
  LprD2 = ""; if (lmPlaced("dors2Origin")) LprD2 = mHproj("LprD2", xD, getLMx("dors2Origin"), yB, "", "");
  LbD2  = ""; if (lmPlaced("dors2End"))    LbD2  = mLM("LbD2", "dors2Origin", "dors2End");
  DD1D2 = ""; if (lmPlaced("dors2Origin")) DD1D2 = mLM("DD1D2", "dorsEnd", "dors2Origin");
  LBarb = ""; if (lmPlaced("barbelTip"))   LBarb = mLM("LBarb", "barbelBase", "barbelTip");
  LbAd  = ""; if (lmPlaced("adiposeEnd"))  LbAd  = mLM("LbAd", "adiposeOrigin", "adiposeEnd");
  LMax  = ""; if (lmPlaced("maxillaEnd"))  LMax  = mLM("LMax", "snoutTip", "maxillaEnd");
  HD    = ""; if (lmPlaced("dorsRayTip"))  HD    = mLM("HD", "dorsOrigin", "dorsRayTip");
  HA    = ""; if (lmPlaced("analRayTip"))  HA    = mLM("HA", "analOrigin", "analRayTip");
  // -- v1: 5 additional optional measurements (full specification) --
  L2D  = ""; if (lmPlaced("dors2RayTip"))   L2D  = mLM("L2D", "dors2Origin", "dors2RayTip");
  LEPc = ""; if (lmPlaced("pecSpineTip"))   LEPc = mLM("LEPc", "pecOrigin", "pecSpineTip");
  L1ED = ""; if (lmPlaced("dorsSpine1Tip")) L1ED = mLM("L1ED", "dorsSpine1Base", "dorsSpine1Tip");
  L2ED = ""; if (lmPlaced("dorsSpine2Tip")) L2ED = mLM("L2ED", "dorsSpine2Base", "dorsSpine2Tip");
  L3ED = ""; if (lmPlaced("dorsSpine3Tip")) L3ED = mLM("L3ED", "dorsSpine3Base", "dorsSpine3Tip");

  // traitValues in full 1 -> 57 order (bodyH = trait 24 "H").
  traitValues = newArray(
    TL,SL,LprA,LbA,LprPl,LbPl,LPl,LprPc,LbPc,LPc,
    LprD,LbD,LbDE,LbDM,HL,LEJ,LprO,LpsO,Mu,DO,
    DSO,Hte,HM,bodyH,DDEPl,DDEPc,DDEA,DDMPl,DDMPc,DDMA,DPcPl,
    DPcA,DPlA,HPC,LPC1,LPC2,LC,HC,L1EA,L2EA,E2EA,
    L3EA,LEPl,L4ED,
    LprD2,LbD2,DD1D2,LBarb,LbAd,LMax,HD,HA,
    L2D,LEPc,L1ED,L2ED,L3ED);

  t1 = getTime;
  time = (t1 - t0) / 1000;

  setBatchMode(false);
}

function setMorphoTable(i) {
  Table.set("image_id", i, title);
  Table.set("px.cm", i, pxcm);
  // Measurements converted to the entered scale unit (mm/cm/inch), like ImageJ: pixels / px.cm.
  // Without a scale (px.cm == "NA"), raw pixels are kept.
  for (k = 0; k < traitCodes.length; k++) {
    if (!isSelected(k)) continue;
    tv = traitValues[k];
    if (pxcm != "NA") {
      v = tv / pxcm;
      v = v * unitFactor;
    } else {
      v = tv;
    }
    Table.set(traitCodes[k], i, v);
  }
  Table.set("time", i, time);
}

//---------------------------  FULL ANALYSIS (single image / batch)  ---------------------//

function singleAnalysis() {
  checkImage("s");
  duplicateImage();
  run("ROI Manager...");
  roiManager("Show All with labels");
  run("Colors...", "foreground=black background=white selection=red");

  // Reset the step flags: without this, running "Single image" a 2nd time in
  // the same Fiji session would skip everything (the "_done" flags stayed
  // true from the previous analysis).
  resetAnalysisFlags();
  inBatch = false;

  askTraitSelection();       // v1: choose the measurements BEFORE placement
  morphoAnalysis();

  Table.create("Traits");
  setMorphoTable(0);
}

function multiAnalysis() {
  imgFolder = getDirectory("Select the folder of images to analyze");
  imgNames = listImages(imgFolder);

  if (imgNames.length == 0) {
    exit("<html>No image (.jpg/.jpeg/.png/.tif/.tiff/.bmp) found in this folder.");
  }

  askTraitSelection();

  run("ROI Manager...");
  run("Colors...", "foreground=black background=white selection=red");

  Table.create("Traits");

  inBatch = true;
  nProcessed = 0;
  runBatchFrom(0);
}

// Processes imgNames starting at index startIdx (used by
// multiAnalysis() at the start, and by continueAnalysis()
// to resume the rest of the batch after finishing the image that was
// interrupted).
function runBatchFrom(startIdx) {
  stopNow = false;
  for (batchIdx = startIdx; batchIdx < imgNames.length && !stopNow; batchIdx++) {
    imgPath = imgFolder + imgNames[batchIdx];
    if (!File.exists(imgPath)) {
      print("Image not found, skipped: " + imgPath);
      continue;
    }

    open(imgPath);
    duplicateImage();

    roiManager("reset");
    roiManager("Show All with labels");

    // Reset the step flags for each new image: without this, from the 2nd
    // image onward morphoAnalysis() would skip scale/outline/lines/landmarks,
    // reusing the "_done" flags left true from the previous image.
    resetAnalysisFlags();
    resuming = false;
    morphoAnalysis();
    setMorphoTable(nProcessed);

    roiManager("Deselect");
    close();
    nProcessed = nProcessed + 1;

    remaining = imgNames.length - batchIdx - 1;
    if (remaining > 0) {
      Dialog.createNonBlocking("Next image");
      Dialog.addMessage((batchIdx + 1) + " image(s) processed this session.\n" +
                        remaining + " image(s) remaining.");
      Dialog.addCheckbox("Stop here", false);
      Dialog.show();
      stopNow = Dialog.getCheckbox();
    }
  }

  finishBatch();
}

function finishBatch() {
  if (isOpen("ROI Manager")) {
    selectWindow("ROI Manager");
    run("Close");
  }
  inBatch = false;

  tableName = "Traits";
  showMessage("<html>Analysis complete.<br>" + nProcessed + " fish processed this session.<br><br>The \"" + tableName + "\" table contains all results.<br>Use File > Export to save.");
}

//----------------------------------------  MACROS  ----------------------------------------//

// Command names distinct from every other MetricFishJ install (French v1/v2,
// English v1): ImageJ installs macros into an application-wide command table
// shared by ALL plugins loaded in the same Fiji session. Identical names would
// silently overwrite one another if several GUIs are opened in turn.

function continueAnalysis() {
  list = getList("image.titles");
  if (list.length == 0) {
    exit("<html>No image open. Open an image before continuing.");
  }
  if (list.length > 1) {
    exit("<html>Several images are open. Close them first.");
  }

  stepMsg = "Step detected: ";

  if (!scale_done) {
    stepMsg = stepMsg + "Scale";
  } else if (!adjust_done) {
    stepMsg = stepMsg + "Adjustment (rotation/straightening)";
  } else if (!orient_done) {
    stepMsg = stepMsg + "Orientation";
  } else if (!outline_done) {
    stepMsg = stepMsg + "Fish outline";
  } else if (!lines_done) {
    stepMsg = stepMsg + "Reference lines (D/A/H/E) - restarting from the beginning";
    // Reinitialize lines to restart from scratch
    for (ln = 0; ln < 4; ln++) deleteRoiIfExists(lineNames[ln]);
    lines_done = false;
  } else if (LMok.length == 0 || sumArray(LMok) == 0) {
    stepMsg = stepMsg + "Base landmarks";
  } else if (!landmarks_done || (LMok.length > 0 && sumArray(LMok) < 33)) {
    // Base landmarks not completed: find next point and restart it
    currentIdx = -1;
    for (k = 0; k < 33; k++) {
      if (k >= LMok.length || LMok[k] == 0) {
        currentIdx = k;
        break;
      }
    }
    if (currentIdx >= 0 && currentIdx < lmCodes.length) {
      stepMsg = stepMsg + "Landmark " + lmCodes[currentIdx] + " - restarting from the beginning";
      deleteRoiIfExists(lmCodes[currentIdx]);
      if (currentIdx < LMok.length) LMok[currentIdx] = 0;
    }
  } else if (!optional_done) {
    stepMsg = stepMsg + "Group A landmarks (optional)";
  } else {
    stepMsg = stepMsg + "Analysis completed";
  }

  showMessage("<html>Resuming analysis.<br><br>" + stepMsg);

  run("ROI Manager...");
  roiManager("Show All with labels");
  resuming = true;
  morphoAnalysis();

  // inBatch alone isn't enough: if the batch was interrupted BEFORE its
  // context (folder/list/index) was actually set (e.g. closing the "Select
  // measurements" dialog right after choosing the folder), inBatch could be
  // inconsistent with imgNames/batchIdx still at their default values. Check
  // full consistency before using this context, otherwise fall back cleanly
  // to the single-image path instead of crashing.
  batchContextOk = inBatch && imgNames.length > 0 && batchIdx >= 0 && batchIdx < imgNames.length;

  if (batchContextOk) {
    // We were in the middle of a batch: finish this image (table + close)
    // then resume the loop over the remaining images in the folder, exactly
    // like multiAnalysis() itself would.
    setMorphoTable(nProcessed);
    roiManager("Deselect");
    close();
    nProcessed = nProcessed + 1;

    remaining = imgNames.length - batchIdx - 1;
    if (remaining > 0) {
      Dialog.createNonBlocking("Next image");
      Dialog.addMessage((batchIdx + 1) + " image(s) processed this session.\n" +
                        remaining + " image(s) remaining.");
      Dialog.addCheckbox("Stop here", false);
      Dialog.show();
      stopNow = Dialog.getCheckbox();
      if (!stopNow) {
        runBatchFrom(batchIdx + 1);
        return;
      }
    }
    finishBatch();
  } else {
    // Single image (or inconsistent batch context): (re)display the results
    // table, even if the user had closed the previous one - otherwise
    // "Continue" finishes the analysis silently without showing the result.
    inBatch = false;   // avoid getting stuck on an inconsistent batch state
    Table.create("Traits");
    setMorphoTable(0);
  }
}

function sumArray(arr) {
  // Uses "var sIdx" (NOT "i"): "i" is the global batch image index used by
  // continueAnalysis()/runBatchFrom() - reusing it here without "var" would
  // silently clobber it every time sumArray() is called during step
  // detection, corrupting batch resumption.
  var sIdx;
  sum = 0;
  for (sIdx = 0; sIdx < arr.length; sIdx++) sum = sum + arr[sIdx];
  return sum;
}

macro "MetricFishJ Traits v1 EN" {
  singleAnalysis();
}

macro "MetricFishJ Traits Multi v1 EN" {
  multiAnalysis();
}

macro "MetricFishJ Continue v1 EN" {
  continueAnalysis();
}
