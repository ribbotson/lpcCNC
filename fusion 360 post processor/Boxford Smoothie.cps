adescription = "Boxford Shapeoko";
vendor = "rLab";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic post for Boxford Shapeoko";

extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion
highFeedrate = (unit == IN) ? 100 : 1000;

// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeTools: true, // writes the tools
  showSequenceNumbers: false, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 1, // increment for sequence numbers
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
};

// user-defined property definitions
propertyDefinitions = {
  writeMachine: { title: "Write machine", description: "Output the machine settings in the header of the code.", group: 0, type: "boolean" },
  writeTools: { title: "Write tool list", description: "Output a tool list in the header of the code.", group: 0, type: "boolean" },
  showSequenceNumbers: { title: "Use sequence numbers", description: "Use sequence numbers for each block of outputted code.", group: 1, type: "boolean" },
  sequenceNumberStart: { title: "Start sequence number", description: "The number at which to start the sequence numbers.", group: 1, type: "integer" },
  sequenceNumberIncrement: { title: "Sequence number increment", description: "The amount by which the sequence number is incremented by in each block.", group: 1, type: "integer" },
  separateWordsWithSpace: { title: "Separate words with space", description: "Adds spaces between words if 'yes' is selected.", type: "boolean" },
};

var numberOfToolSlots = 9999;

var gFormat = createFormat({ prefix: "G", decimals: 0 });
var mFormat = createFormat({ prefix: "M", decimals: 0 });
var tFormat = createFormat({ prefix: "T", decimals: 0 });

var xyzFormat = createFormat({ decimals: (unit == MM ? 3 : 4) });
var feedFormat = createFormat({ decimals: (unit == MM ? 2 : 3) });
var toolFormat = createFormat({ decimals: 0 });
var rpmFormat = createFormat({ decimals: 0 });
var powerFormat = createFormat({ decimals: 2 });
var secFormat = createFormat({ decimals: 3, forceDecimal: true }); // seconds - range 0.001-1000
var taperFormat = createFormat({ decimals: 1, scale: DEG });

var xOutput = createVariable({ prefix: "X" }, xyzFormat);
var yOutput = createVariable({ prefix: "Y" }, xyzFormat);
var zOutput = createVariable({ prefix: "Z" }, xyzFormat);
var feedOutput = createVariable({ prefix: "F" }, feedFormat);
var sOutput = createVariable({ prefix: "S", force: false }, rpmFormat);
var powerOutput = createVariable({ prefix: "S", force: false }, powerFormat);

// circular output
var iOutput = createReferenceVariable({ prefix: "I" }, xyzFormat);
var jOutput = createReferenceVariable({ prefix: "J" }, xyzFormat);
var kOutput = createReferenceVariable({ prefix: "K" }, xyzFormat);

var gMotionModal = createModal({ force: true }, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({ onchange: function () { gMotionModal.reset(); } }, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal = createModal({}, gFormat); // modal group 10 // G98-99

var WARNING_WORK_OFFSET = 0;

var pendingRadiusCompensation = -1;

var shapeArea = 0;
var shapePerimeter = 0;
var shapeSide = "inner";
var cuttingSequence = "";
var sequenceNumber;
var currentWorkOffset;

var command = {
  spindle_start: function (rpms, direction) {
    if (direction == tool.clockwise) {
      writeBlock(mFormat.format(3), "S" + rpms, formatComment("Start spindle forwards"))
    } else {
      writeBlock(mFormat.format(4), sOutput.format(rpms), formatComment("Start spindle reverse"));
    }
  },
  spindle_stop: function () {
    writeBlock(mFormat.format(5), formatComment('Stop spindle'));
  },
  home_position_z: function () {
    writeBlock(gFormat.format(53), gFormat.format(0), "Z" + xyzFormat.format(0), formatComment('Go to z-home'))
  },
  home_position_xy: function () {
    writeBlock(
      gFormat.format(53),
      gFormat.format(0),
      "X" + xyzFormat.format(0),
      "Y" + xyzFormat.format(0),
      "Z" + xyzFormat.format(0),
      formatComment('Go to xy-home')
    )
  },
  coolant_on: function () {
    writeBlock(mFormat.format(7), formatComment('Coolant On'));
    writeBlock(mFormat.format(8), formatComment('Coolant On'));
  },
  coolant_off: function () {
    writeBlock(mFormat.format(9), formatComment('Coolant Off'));
  },
  tool_change: function (tool_number) {
    writeComment('Tool Change')
    command.coolant_off()
    command.spindle_stop()
    command.home_position_z()
    if (tool.comment) {
      writeComment(tool.comment);
    }
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      var zRange = currentSection.getGlobalZRange();
      var number = tool.number;
      for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
        var section = getSection(i);
        if (section.getTool().number != number) {
          break;
        }
        zRange.expandToRange(section.getGlobalZRange());
      }
    }
    writeBlock(mFormat.format(6), tFormat.format(tool_number),formatComment("Tool information:  z-minimum =" + zRange.getMinimum()));
    writeln("");
    writeln("");
    writeln("");
  },
  end_cycle: function () {
    writeComment('End Cycle')
    command.spindle_stop()
    command.coolant_off()
    command.home_position_z()
    command.home_position_xy()
    writeln("%");
  }
}
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}
function formatComment(text) {
  return "; " + String(text).replace(/[\(\)]/g, "");
}
function writeComment(text) {
  writeln(formatComment(text));
}
function onOpen() {
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
  writeln("%");

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": " + description);
    }
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + " " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90), formatComment('Absolute mode'));
  writeBlock(gPlaneModal.format(17), formatComment('Select XYZ plane'));

  switch (unit) {
    case IN:
      writeBlock(gUnitModal.format(20), formatComment('Inch Mode'));
      break;
    case MM:
      writeBlock(gUnitModal.format(21), formatComment('Millimeter Mode'));
      break;
  }
  writeln('')
  writeln('')
  writeln('')
}
function onComment(message) {
  writeln("");
  writeComment(message);
}
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}
function onSection() {
  var insertToolCall = isFirstSection() || currentSection.getForceToolChange && currentSection.getForceToolChange() || (tool.number != getPreviousSection().getTool().number);
  var newWorkOffset = isFirstSection() || (getPreviousSection().workOffset != currentSection.workOffset);
  var newWorkPlane = isFirstSection() || !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

  //tool change code
  if (insertToolCall) {
    command.tool_change(tool.number)
  }

  //operation comment
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  command.spindle_start(tool.spindleRPM, tool.clockwise)

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  writeBlock(
    gAbsIncModal.format(90),
    gMotionModal.format(0),
    xOutput.format(initialPosition.x),
    yOutput.format(initialPosition.y)
  );
}
function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "S" + secFormat.format(seconds));
}
function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}
function onCycle() {
  writeBlock(gPlaneModal.format(17));
}
function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
  zOutput.format(z),
  "R" + xyzFormat.format(r)];
}
function onCyclePoint(x, y, z) {
  if (!properties.useCycles) {
    expandCyclePoint(x, y, z);
    return;
  }
}
function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}
function onParameter(name, value) {
  if ((name == "action") && (value == "pierce")) {
    // add delay if desired
  } else if (name == "shapeArea") {
    shapeArea = value;
  } else if (name == "shapePerimeter") {
    shapePerimeter = value;
  } else if (name == "shapeSide") {
    shapeSide = value;
  } else if (name == "beginSequence") {
    if (value == "piercing") {
      if (cuttingSequence != "piercing") {
        if (properties.allowHeadSwitches) {
          // Allow head to be switched here
        }
      }
    } else if (value == "cutting") {
      if (cuttingSequence == "piercing") {
        if (properties.allowHeadSwitches) {
          // Allow head to be switched here
        }
      }
    }
    cuttingSequence = value;
  }
}
function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z);
  }
}
function onLinear(_x, _y, _z, feed) {
  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode is not supported."));
      return;
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) {
      feedOutput.reset();
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}
function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("Multi-axis motion is not supported."));
}
function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("Multi-axis motion is not supported."));
}
function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
      case PLANE_XY:
        writeBlock(
          gPlaneModal.format(17),
          gMotionModal.format(clockwise ? 2 : 3),
          xOutput.format(x),
          iOutput.format(cx - start.x, 0),
          jOutput.format(cy - start.y, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      case PLANE_ZX:
        writeBlock(
          gPlaneModal.format(18),
          gMotionModal.format(clockwise ? 2 : 3),
          zOutput.format(z),
          iOutput.format(cx - start.x, 0),
          kOutput.format(cz - start.z, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      case PLANE_YZ:
        writeBlock(
          gPlaneModal.format(19),
          gMotionModal.format(clockwise ? 2 : 3),
          yOutput.format(y),
          jOutput.format(cy - start.y, 0),
          kOutput.format(cz - start.z, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      default:
        linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
      case PLANE_XY:
        writeBlock(
          gPlaneModal.format(17),
          gMotionModal.format(clockwise ? 2 : 3),
          xOutput.format(x),
          yOutput.format(y),
          zOutput.format(z),
          iOutput.format(cx - start.x, 0),
          jOutput.format(cy - start.y, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      case PLANE_ZX:
        writeBlock(
          gPlaneModal.format(18),
          gMotionModal.format(clockwise ? 2 : 3),
          xOutput.format(x),
          yOutput.format(y),
          zOutput.format(z),
          iOutput.format(cx - start.x, 0),
          kOutput.format(cz - start.z, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      case PLANE_YZ:
        writeBlock(
          gPlaneModal.format(19),
          gMotionModal.format(clockwise ? 2 : 3),
          xOutput.format(x),
          yOutput.format(y),
          zOutput.format(z),
          jOutput.format(cy - start.y, 0),
          kOutput.format(cz - start.z, 0),
          feedOutput.format(feed)
        );
        gMotionModal.reset();
        break;
      default:
        linearize(tolerance);
    }
  }
}
function onSectionEnd() {
  writeBlock(gPlaneModal.format(17));
  forceAny();
  writeComment('Section End')
  writeln("");
  writeln("");
  writeln("");
}
function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}
function onClose() {
  command.end_cycle()
}
