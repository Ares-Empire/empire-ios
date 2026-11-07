"use strict";
var __AresiumEngine = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from2, except, desc) => {
    if (from2 && typeof from2 === "object" || typeof from2 === "function") {
      for (let key of __getOwnPropNames(from2))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from2[key], enumerable: !(desc = __getOwnPropDesc(from2, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // node_modules/fast-xml-parser/src/util.js
  var require_util = __commonJS({
    "node_modules/fast-xml-parser/src/util.js"(exports) {
      "use strict";
      var nameStartChar = ":A-Za-z_\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02FF\\u0370-\\u037D\\u037F-\\u1FFF\\u200C-\\u200D\\u2070-\\u218F\\u2C00-\\u2FEF\\u3001-\\uD7FF\\uF900-\\uFDCF\\uFDF0-\\uFFFD";
      var nameChar = nameStartChar + "\\-.\\d\\u00B7\\u0300-\\u036F\\u203F-\\u2040";
      var nameRegexp = "[" + nameStartChar + "][" + nameChar + "]*";
      var regexName = new RegExp("^" + nameRegexp + "$");
      var getAllMatches = function(string, regex) {
        const matches = [];
        let match = regex.exec(string);
        while (match) {
          const allmatches = [];
          allmatches.startIndex = regex.lastIndex - match[0].length;
          const len = match.length;
          for (let index = 0; index < len; index++) {
            allmatches.push(match[index]);
          }
          matches.push(allmatches);
          match = regex.exec(string);
        }
        return matches;
      };
      var isName = function(string) {
        const match = regexName.exec(string);
        return !(match === null || typeof match === "undefined");
      };
      exports.isExist = function(v) {
        return typeof v !== "undefined";
      };
      exports.isEmptyObject = function(obj) {
        return Object.keys(obj).length === 0;
      };
      exports.merge = function(target, a, arrayMode) {
        if (a) {
          const keys = Object.keys(a);
          const len = keys.length;
          for (let i2 = 0; i2 < len; i2++) {
            if (arrayMode === "strict") {
              target[keys[i2]] = [a[keys[i2]]];
            } else {
              target[keys[i2]] = a[keys[i2]];
            }
          }
        }
      };
      exports.getValue = function(v) {
        if (exports.isExist(v)) {
          return v;
        } else {
          return "";
        }
      };
      var DANGEROUS_PROPERTY_NAMES = [
        // '__proto__',
        // 'constructor',
        // 'prototype',
        "hasOwnProperty",
        "toString",
        "valueOf",
        "__defineGetter__",
        "__defineSetter__",
        "__lookupGetter__",
        "__lookupSetter__"
      ];
      var criticalProperties = ["__proto__", "constructor", "prototype"];
      exports.isName = isName;
      exports.getAllMatches = getAllMatches;
      exports.nameRegexp = nameRegexp;
      exports.DANGEROUS_PROPERTY_NAMES = DANGEROUS_PROPERTY_NAMES;
      exports.criticalProperties = criticalProperties;
    }
  });

  // node_modules/fast-xml-parser/src/validator.js
  var require_validator = __commonJS({
    "node_modules/fast-xml-parser/src/validator.js"(exports) {
      "use strict";
      var util = require_util();
      var defaultOptions = {
        allowBooleanAttributes: false,
        //A tag can have attributes without any value
        unpairedTags: []
      };
      exports.validate = function(xmlData, options) {
        options = Object.assign({}, defaultOptions, options);
        const tags = [];
        let tagFound = false;
        let reachedRoot = false;
        if (xmlData[0] === "\uFEFF") {
          xmlData = xmlData.substr(1);
        }
        for (let i2 = 0; i2 < xmlData.length; i2++) {
          if (xmlData[i2] === "<" && xmlData[i2 + 1] === "?") {
            i2 += 2;
            i2 = readPI(xmlData, i2);
            if (i2.err) return i2;
          } else if (xmlData[i2] === "<") {
            let tagStartPos = i2;
            i2++;
            if (xmlData[i2] === "!") {
              i2 = readCommentAndCDATA(xmlData, i2);
              continue;
            } else {
              let closingTag = false;
              if (xmlData[i2] === "/") {
                closingTag = true;
                i2++;
              }
              let tagName = "";
              for (; i2 < xmlData.length && xmlData[i2] !== ">" && xmlData[i2] !== " " && xmlData[i2] !== "	" && xmlData[i2] !== "\n" && xmlData[i2] !== "\r"; i2++) {
                tagName += xmlData[i2];
              }
              tagName = tagName.trim();
              if (tagName[tagName.length - 1] === "/") {
                tagName = tagName.substring(0, tagName.length - 1);
                i2--;
              }
              if (!validateTagName(tagName)) {
                let msg;
                if (tagName.trim().length === 0) {
                  msg = "Invalid space after '<'.";
                } else {
                  msg = "Tag '" + tagName + "' is an invalid name.";
                }
                return getErrorObject("InvalidTag", msg, getLineNumberForPosition(xmlData, i2));
              }
              const result = readAttributeStr(xmlData, i2);
              if (result === false) {
                return getErrorObject("InvalidAttr", "Attributes for '" + tagName + "' have open quote.", getLineNumberForPosition(xmlData, i2));
              }
              let attrStr = result.value;
              i2 = result.index;
              if (attrStr[attrStr.length - 1] === "/") {
                const attrStrStart = i2 - attrStr.length;
                attrStr = attrStr.substring(0, attrStr.length - 1);
                const isValid = validateAttributeString(attrStr, options);
                if (isValid === true) {
                  tagFound = true;
                } else {
                  return getErrorObject(isValid.err.code, isValid.err.msg, getLineNumberForPosition(xmlData, attrStrStart + isValid.err.line));
                }
              } else if (closingTag) {
                if (!result.tagClosed) {
                  return getErrorObject("InvalidTag", "Closing tag '" + tagName + "' doesn't have proper closing.", getLineNumberForPosition(xmlData, i2));
                } else if (attrStr.trim().length > 0) {
                  return getErrorObject("InvalidTag", "Closing tag '" + tagName + "' can't have attributes or invalid starting.", getLineNumberForPosition(xmlData, tagStartPos));
                } else if (tags.length === 0) {
                  return getErrorObject("InvalidTag", "Closing tag '" + tagName + "' has not been opened.", getLineNumberForPosition(xmlData, tagStartPos));
                } else {
                  const otg = tags.pop();
                  if (tagName !== otg.tagName) {
                    let openPos = getLineNumberForPosition(xmlData, otg.tagStartPos);
                    return getErrorObject(
                      "InvalidTag",
                      "Expected closing tag '" + otg.tagName + "' (opened in line " + openPos.line + ", col " + openPos.col + ") instead of closing tag '" + tagName + "'.",
                      getLineNumberForPosition(xmlData, tagStartPos)
                    );
                  }
                  if (tags.length == 0) {
                    reachedRoot = true;
                  }
                }
              } else {
                const isValid = validateAttributeString(attrStr, options);
                if (isValid !== true) {
                  return getErrorObject(isValid.err.code, isValid.err.msg, getLineNumberForPosition(xmlData, i2 - attrStr.length + isValid.err.line));
                }
                if (reachedRoot === true) {
                  return getErrorObject("InvalidXml", "Multiple possible root nodes found.", getLineNumberForPosition(xmlData, i2));
                } else if (options.unpairedTags.indexOf(tagName) !== -1) {
                } else {
                  tags.push({ tagName, tagStartPos });
                }
                tagFound = true;
              }
              for (i2++; i2 < xmlData.length; i2++) {
                if (xmlData[i2] === "<") {
                  if (xmlData[i2 + 1] === "!") {
                    i2++;
                    i2 = readCommentAndCDATA(xmlData, i2);
                    continue;
                  } else if (xmlData[i2 + 1] === "?") {
                    i2 = readPI(xmlData, ++i2);
                    if (i2.err) return i2;
                  } else {
                    break;
                  }
                } else if (xmlData[i2] === "&") {
                  const afterAmp = validateAmpersand(xmlData, i2);
                  if (afterAmp == -1)
                    return getErrorObject("InvalidChar", "char '&' is not expected.", getLineNumberForPosition(xmlData, i2));
                  i2 = afterAmp;
                } else {
                  if (reachedRoot === true && !isWhiteSpace(xmlData[i2])) {
                    return getErrorObject("InvalidXml", "Extra text at the end", getLineNumberForPosition(xmlData, i2));
                  }
                }
              }
              if (xmlData[i2] === "<") {
                i2--;
              }
            }
          } else {
            if (isWhiteSpace(xmlData[i2])) {
              continue;
            }
            return getErrorObject("InvalidChar", "char '" + xmlData[i2] + "' is not expected.", getLineNumberForPosition(xmlData, i2));
          }
        }
        if (!tagFound) {
          return getErrorObject("InvalidXml", "Start tag expected.", 1);
        } else if (tags.length == 1) {
          return getErrorObject("InvalidTag", "Unclosed tag '" + tags[0].tagName + "'.", getLineNumberForPosition(xmlData, tags[0].tagStartPos));
        } else if (tags.length > 0) {
          return getErrorObject("InvalidXml", "Invalid '" + JSON.stringify(tags.map((t) => t.tagName), null, 4).replace(/\r?\n/g, "") + "' found.", { line: 1, col: 1 });
        }
        return true;
      };
      function isWhiteSpace(char) {
        return char === " " || char === "	" || char === "\n" || char === "\r";
      }
      function readPI(xmlData, i2) {
        const start = i2;
        for (; i2 < xmlData.length; i2++) {
          if (xmlData[i2] == "?" || xmlData[i2] == " ") {
            const tagname = xmlData.substr(start, i2 - start);
            if (i2 > 5 && tagname === "xml") {
              return getErrorObject("InvalidXml", "XML declaration allowed only at the start of the document.", getLineNumberForPosition(xmlData, i2));
            } else if (xmlData[i2] == "?" && xmlData[i2 + 1] == ">") {
              i2++;
              break;
            } else {
              continue;
            }
          }
        }
        return i2;
      }
      function readCommentAndCDATA(xmlData, i2) {
        if (xmlData.length > i2 + 5 && xmlData[i2 + 1] === "-" && xmlData[i2 + 2] === "-") {
          for (i2 += 3; i2 < xmlData.length; i2++) {
            if (xmlData[i2] === "-" && xmlData[i2 + 1] === "-" && xmlData[i2 + 2] === ">") {
              i2 += 2;
              break;
            }
          }
        } else if (xmlData.length > i2 + 8 && xmlData[i2 + 1] === "D" && xmlData[i2 + 2] === "O" && xmlData[i2 + 3] === "C" && xmlData[i2 + 4] === "T" && xmlData[i2 + 5] === "Y" && xmlData[i2 + 6] === "P" && xmlData[i2 + 7] === "E") {
          let angleBracketsCount = 1;
          for (i2 += 8; i2 < xmlData.length; i2++) {
            if (xmlData[i2] === "<") {
              angleBracketsCount++;
            } else if (xmlData[i2] === ">") {
              angleBracketsCount--;
              if (angleBracketsCount === 0) {
                break;
              }
            }
          }
        } else if (xmlData.length > i2 + 9 && xmlData[i2 + 1] === "[" && xmlData[i2 + 2] === "C" && xmlData[i2 + 3] === "D" && xmlData[i2 + 4] === "A" && xmlData[i2 + 5] === "T" && xmlData[i2 + 6] === "A" && xmlData[i2 + 7] === "[") {
          for (i2 += 8; i2 < xmlData.length; i2++) {
            if (xmlData[i2] === "]" && xmlData[i2 + 1] === "]" && xmlData[i2 + 2] === ">") {
              i2 += 2;
              break;
            }
          }
        }
        return i2;
      }
      var doubleQuote = '"';
      var singleQuote = "'";
      function readAttributeStr(xmlData, i2) {
        let attrStr = "";
        let startChar = "";
        let tagClosed = false;
        for (; i2 < xmlData.length; i2++) {
          if (xmlData[i2] === doubleQuote || xmlData[i2] === singleQuote) {
            if (startChar === "") {
              startChar = xmlData[i2];
            } else if (startChar !== xmlData[i2]) {
            } else {
              startChar = "";
            }
          } else if (xmlData[i2] === ">") {
            if (startChar === "") {
              tagClosed = true;
              break;
            }
          }
          attrStr += xmlData[i2];
        }
        if (startChar !== "") {
          return false;
        }
        return {
          value: attrStr,
          index: i2,
          tagClosed
        };
      }
      var validAttrStrRegxp = new RegExp(`(\\s*)([^\\s=]+)(\\s*=)?(\\s*(['"])(([\\s\\S])*?)\\5)?`, "g");
      function validateAttributeString(attrStr, options) {
        const matches = util.getAllMatches(attrStr, validAttrStrRegxp);
        const attrNames = {};
        for (let i2 = 0; i2 < matches.length; i2++) {
          if (matches[i2][1].length === 0) {
            return getErrorObject("InvalidAttr", "Attribute '" + matches[i2][2] + "' has no space in starting.", getPositionFromMatch(matches[i2]));
          } else if (matches[i2][3] !== void 0 && matches[i2][4] === void 0) {
            return getErrorObject("InvalidAttr", "Attribute '" + matches[i2][2] + "' is without value.", getPositionFromMatch(matches[i2]));
          } else if (matches[i2][3] === void 0 && !options.allowBooleanAttributes) {
            return getErrorObject("InvalidAttr", "boolean attribute '" + matches[i2][2] + "' is not allowed.", getPositionFromMatch(matches[i2]));
          }
          const attrName = matches[i2][2];
          if (!validateAttrName(attrName)) {
            return getErrorObject("InvalidAttr", "Attribute '" + attrName + "' is an invalid name.", getPositionFromMatch(matches[i2]));
          }
          if (!attrNames.hasOwnProperty(attrName)) {
            attrNames[attrName] = 1;
          } else {
            return getErrorObject("InvalidAttr", "Attribute '" + attrName + "' is repeated.", getPositionFromMatch(matches[i2]));
          }
        }
        return true;
      }
      function validateNumberAmpersand(xmlData, i2) {
        let re = /\d/;
        if (xmlData[i2] === "x") {
          i2++;
          re = /[\da-fA-F]/;
        }
        for (; i2 < xmlData.length; i2++) {
          if (xmlData[i2] === ";")
            return i2;
          if (!xmlData[i2].match(re))
            break;
        }
        return -1;
      }
      function validateAmpersand(xmlData, i2) {
        i2++;
        if (xmlData[i2] === ";")
          return -1;
        if (xmlData[i2] === "#") {
          i2++;
          return validateNumberAmpersand(xmlData, i2);
        }
        let count = 0;
        for (; i2 < xmlData.length; i2++, count++) {
          if (xmlData[i2].match(/\w/) && count < 20)
            continue;
          if (xmlData[i2] === ";")
            break;
          return -1;
        }
        return i2;
      }
      function getErrorObject(code, message, lineNumber) {
        return {
          err: {
            code,
            msg: message,
            line: lineNumber.line || lineNumber,
            col: lineNumber.col
          }
        };
      }
      function validateAttrName(attrName) {
        return util.isName(attrName);
      }
      function validateTagName(tagname) {
        return util.isName(tagname);
      }
      function getLineNumberForPosition(xmlData, index) {
        const lines = xmlData.substring(0, index).split(/\r?\n/);
        return {
          line: lines.length,
          // column number is last line's length + 1, because column numbering starts at 1:
          col: lines[lines.length - 1].length + 1
        };
      }
      function getPositionFromMatch(match) {
        return match.startIndex + match[1].length;
      }
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/OptionsBuilder.js
  var require_OptionsBuilder = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/OptionsBuilder.js"(exports) {
      var { DANGEROUS_PROPERTY_NAMES, criticalProperties } = require_util();
      var defaultOnDangerousProperty = (name) => {
        if (DANGEROUS_PROPERTY_NAMES.includes(name)) {
          return "__" + name;
        }
        return name;
      };
      var defaultOptions = {
        preserveOrder: false,
        attributeNamePrefix: "@_",
        attributesGroupName: false,
        textNodeName: "#text",
        ignoreAttributes: true,
        removeNSPrefix: false,
        // remove NS from tag name or attribute name if true
        allowBooleanAttributes: false,
        //a tag can have attributes without any value
        //ignoreRootElement : false,
        parseTagValue: true,
        parseAttributeValue: false,
        trimValues: true,
        //Trim string values of tag and attributes
        cdataPropName: false,
        numberParseOptions: {
          hex: true,
          leadingZeros: true,
          eNotation: true
        },
        tagValueProcessor: function(tagName, val) {
          return val;
        },
        attributeValueProcessor: function(attrName, val) {
          return val;
        },
        stopNodes: [],
        //nested tags will not be parsed even for errors
        alwaysCreateTextNode: false,
        isArray: () => false,
        commentPropName: false,
        unpairedTags: [],
        processEntities: true,
        htmlEntities: false,
        ignoreDeclaration: false,
        ignorePiTags: false,
        transformTagName: false,
        transformAttributeName: false,
        updateTag: function(tagName, jPath, attrs) {
          return tagName;
        },
        // skipEmptyListItem: false
        captureMetaData: false,
        maxNestedTags: 100,
        strictReservedNames: true,
        onDangerousProperty: defaultOnDangerousProperty
      };
      function validatePropertyName(propertyName, optionName) {
        if (typeof propertyName !== "string") {
          return;
        }
        const normalized = propertyName.toLowerCase();
        if (DANGEROUS_PROPERTY_NAMES.some((dangerous) => normalized === dangerous.toLowerCase())) {
          throw new Error(
            `[SECURITY] Invalid ${optionName}: "${propertyName}" is a reserved JavaScript keyword that could cause prototype pollution`
          );
        }
        if (criticalProperties.some((dangerous) => normalized === dangerous.toLowerCase())) {
          throw new Error(
            `[SECURITY] Invalid ${optionName}: "${propertyName}" is a reserved JavaScript keyword that could cause prototype pollution`
          );
        }
      }
      function normalizeProcessEntities(value) {
        if (typeof value === "boolean") {
          return {
            enabled: value,
            // true or false
            maxEntitySize: 1e4,
            maxExpansionDepth: 10,
            maxTotalExpansions: 1e3,
            maxExpandedLength: 1e5,
            allowedTags: null,
            tagFilter: null
          };
        }
        if (typeof value === "object" && value !== null) {
          return {
            enabled: value.enabled !== false,
            maxEntitySize: Math.max(1, value.maxEntitySize ?? 1e4),
            maxExpansionDepth: Math.max(1, value.maxExpansionDepth ?? 1e4),
            maxTotalExpansions: Math.max(1, value.maxTotalExpansions ?? Infinity),
            maxExpandedLength: Math.max(1, value.maxExpandedLength ?? 1e5),
            maxEntityCount: Math.max(1, value.maxEntityCount ?? 1e3),
            allowedTags: value.allowedTags ?? null,
            tagFilter: value.tagFilter ?? null
          };
        }
        return normalizeProcessEntities(true);
      }
      var buildOptions = function(options) {
        const built = Object.assign({}, defaultOptions, options);
        const propertyNameOptions = [
          { value: built.attributeNamePrefix, name: "attributeNamePrefix" },
          { value: built.attributesGroupName, name: "attributesGroupName" },
          { value: built.textNodeName, name: "textNodeName" },
          { value: built.cdataPropName, name: "cdataPropName" },
          { value: built.commentPropName, name: "commentPropName" }
        ];
        for (const { value, name } of propertyNameOptions) {
          if (value) {
            validatePropertyName(value, name);
          }
        }
        if (built.onDangerousProperty === null) {
          built.onDangerousProperty = defaultOnDangerousProperty;
        }
        built.processEntities = normalizeProcessEntities(built.processEntities);
        return built;
      };
      exports.buildOptions = buildOptions;
      exports.defaultOptions = defaultOptions;
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/xmlNode.js
  var require_xmlNode = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/xmlNode.js"(exports, module) {
      "use strict";
      var XmlNode = class {
        constructor(tagname) {
          this.tagname = tagname;
          this.child = [];
          this[":@"] = {};
        }
        add(key, val) {
          if (key === "__proto__") key = "#__proto__";
          this.child.push({ [key]: val });
        }
        addChild(node2) {
          if (node2.tagname === "__proto__") node2.tagname = "#__proto__";
          if (node2[":@"] && Object.keys(node2[":@"]).length > 0) {
            this.child.push({ [node2.tagname]: node2.child, [":@"]: node2[":@"] });
          } else {
            this.child.push({ [node2.tagname]: node2.child });
          }
        }
      };
      module.exports = XmlNode;
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/DocTypeReader.js
  var require_DocTypeReader = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/DocTypeReader.js"(exports, module) {
      var util = require_util();
      var DocTypeReader = class {
        constructor(options) {
          this.suppressValidationErr = !options;
          this.options = options || {};
        }
        readDocType(xmlData, i2) {
          const entities = /* @__PURE__ */ Object.create(null);
          let entityCount = 0;
          if (xmlData[i2 + 3] === "O" && xmlData[i2 + 4] === "C" && xmlData[i2 + 5] === "T" && xmlData[i2 + 6] === "Y" && xmlData[i2 + 7] === "P" && xmlData[i2 + 8] === "E") {
            i2 = i2 + 9;
            let angleBracketsCount = 1;
            let hasBody = false, comment = false;
            let exp = "";
            for (; i2 < xmlData.length; i2++) {
              if (xmlData[i2] === "<" && !comment) {
                if (hasBody && hasSeq(xmlData, "!ENTITY", i2)) {
                  i2 += 7;
                  let entityName, val;
                  [entityName, val, i2] = this.readEntityExp(xmlData, i2 + 1, this.suppressValidationErr);
                  if (val.indexOf("&") === -1) {
                    if (this.options.enabled !== false && this.options.maxEntityCount != null && entityCount >= this.options.maxEntityCount) {
                      throw new Error(
                        `Entity count (${entityCount + 1}) exceeds maximum allowed (${this.options.maxEntityCount})`
                      );
                    }
                    const escaped = entityName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
                    entities[entityName] = {
                      regx: RegExp(`&${escaped};`, "g"),
                      val
                    };
                    entityCount++;
                  }
                } else if (hasBody && hasSeq(xmlData, "!ELEMENT", i2)) {
                  i2 += 8;
                  const { index } = this.readElementExp(xmlData, i2 + 1);
                  i2 = index;
                } else if (hasBody && hasSeq(xmlData, "!ATTLIST", i2)) {
                  i2 += 8;
                } else if (hasBody && hasSeq(xmlData, "!NOTATION", i2)) {
                  i2 += 9;
                  const { index } = this.readNotationExp(xmlData, i2 + 1, this.suppressValidationErr);
                  i2 = index;
                } else if (hasSeq(xmlData, "!--", i2)) {
                  comment = true;
                } else {
                  throw new Error(`Invalid DOCTYPE`);
                }
                angleBracketsCount++;
                exp = "";
              } else if (xmlData[i2] === ">") {
                if (comment) {
                  if (xmlData[i2 - 1] === "-" && xmlData[i2 - 2] === "-") {
                    comment = false;
                    angleBracketsCount--;
                  }
                } else {
                  angleBracketsCount--;
                }
                if (angleBracketsCount === 0) {
                  break;
                }
              } else if (xmlData[i2] === "[") {
                hasBody = true;
              } else {
                exp += xmlData[i2];
              }
            }
            if (angleBracketsCount !== 0) {
              throw new Error(`Unclosed DOCTYPE`);
            }
          } else {
            throw new Error(`Invalid Tag instead of DOCTYPE`);
          }
          return { entities, i: i2 };
        }
        readEntityExp(xmlData, i2) {
          i2 = skipWhitespace(xmlData, i2);
          let entityName = "";
          while (i2 < xmlData.length && !/\s/.test(xmlData[i2]) && xmlData[i2] !== '"' && xmlData[i2] !== "'") {
            entityName += xmlData[i2];
            i2++;
          }
          validateEntityName(entityName);
          i2 = skipWhitespace(xmlData, i2);
          if (!this.suppressValidationErr) {
            if (xmlData.substring(i2, i2 + 6).toUpperCase() === "SYSTEM") {
              throw new Error("External entities are not supported");
            } else if (xmlData[i2] === "%") {
              throw new Error("Parameter entities are not supported");
            }
          }
          let entityValue = "";
          [i2, entityValue] = this.readIdentifierVal(xmlData, i2, "entity");
          if (this.options.enabled !== false && this.options.maxEntitySize != null && entityValue.length > this.options.maxEntitySize) {
            throw new Error(
              `Entity "${entityName}" size (${entityValue.length}) exceeds maximum allowed size (${this.options.maxEntitySize})`
            );
          }
          i2--;
          return [entityName, entityValue, i2];
        }
        readNotationExp(xmlData, i2) {
          i2 = skipWhitespace(xmlData, i2);
          let notationName = "";
          while (i2 < xmlData.length && !/\s/.test(xmlData[i2])) {
            notationName += xmlData[i2];
            i2++;
          }
          !this.suppressValidationErr && validateEntityName(notationName);
          i2 = skipWhitespace(xmlData, i2);
          const identifierType = xmlData.substring(i2, i2 + 6).toUpperCase();
          if (!this.suppressValidationErr && identifierType !== "SYSTEM" && identifierType !== "PUBLIC") {
            throw new Error(`Expected SYSTEM or PUBLIC, found "${identifierType}"`);
          }
          i2 += identifierType.length;
          i2 = skipWhitespace(xmlData, i2);
          let publicIdentifier = null;
          let systemIdentifier = null;
          if (identifierType === "PUBLIC") {
            [i2, publicIdentifier] = this.readIdentifierVal(xmlData, i2, "publicIdentifier");
            i2 = skipWhitespace(xmlData, i2);
            if (xmlData[i2] === '"' || xmlData[i2] === "'") {
              [i2, systemIdentifier] = this.readIdentifierVal(xmlData, i2, "systemIdentifier");
            }
          } else if (identifierType === "SYSTEM") {
            [i2, systemIdentifier] = this.readIdentifierVal(xmlData, i2, "systemIdentifier");
            if (!this.suppressValidationErr && !systemIdentifier) {
              throw new Error("Missing mandatory system identifier for SYSTEM notation");
            }
          }
          return { notationName, publicIdentifier, systemIdentifier, index: --i2 };
        }
        readIdentifierVal(xmlData, i2, type) {
          let identifierVal = "";
          const startChar = xmlData[i2];
          if (startChar !== '"' && startChar !== "'") {
            throw new Error(`Expected quoted string, found "${startChar}"`);
          }
          i2++;
          while (i2 < xmlData.length && xmlData[i2] !== startChar) {
            identifierVal += xmlData[i2];
            i2++;
          }
          if (xmlData[i2] !== startChar) {
            throw new Error(`Unterminated ${type} value`);
          }
          i2++;
          return [i2, identifierVal];
        }
        readElementExp(xmlData, i2) {
          i2 = skipWhitespace(xmlData, i2);
          let elementName = "";
          while (i2 < xmlData.length && !/\s/.test(xmlData[i2])) {
            elementName += xmlData[i2];
            i2++;
          }
          if (!this.suppressValidationErr && !util.isName(elementName)) {
            throw new Error(`Invalid element name: "${elementName}"`);
          }
          i2 = skipWhitespace(xmlData, i2);
          let contentModel = "";
          if (xmlData[i2] === "E" && hasSeq(xmlData, "MPTY", i2)) {
            i2 += 4;
          } else if (xmlData[i2] === "A" && hasSeq(xmlData, "NY", i2)) {
            i2 += 2;
          } else if (xmlData[i2] === "(") {
            i2++;
            while (i2 < xmlData.length && xmlData[i2] !== ")") {
              contentModel += xmlData[i2];
              i2++;
            }
            if (xmlData[i2] !== ")") {
              throw new Error("Unterminated content model");
            }
          } else if (!this.suppressValidationErr) {
            throw new Error(`Invalid Element Expression, found "${xmlData[i2]}"`);
          }
          return {
            elementName,
            contentModel: contentModel.trim(),
            index: i2
          };
        }
        readAttlistExp(xmlData, i2) {
          i2 = skipWhitespace(xmlData, i2);
          let elementName = "";
          while (i2 < xmlData.length && !/\s/.test(xmlData[i2])) {
            elementName += xmlData[i2];
            i2++;
          }
          validateEntityName(elementName);
          i2 = skipWhitespace(xmlData, i2);
          let attributeName = "";
          while (i2 < xmlData.length && !/\s/.test(xmlData[i2])) {
            attributeName += xmlData[i2];
            i2++;
          }
          if (!validateEntityName(attributeName)) {
            throw new Error(`Invalid attribute name: "${attributeName}"`);
          }
          i2 = skipWhitespace(xmlData, i2);
          let attributeType = "";
          if (xmlData.substring(i2, i2 + 8).toUpperCase() === "NOTATION") {
            attributeType = "NOTATION";
            i2 += 8;
            i2 = skipWhitespace(xmlData, i2);
            if (xmlData[i2] !== "(") {
              throw new Error(`Expected '(', found "${xmlData[i2]}"`);
            }
            i2++;
            let allowedNotations = [];
            while (i2 < xmlData.length && xmlData[i2] !== ")") {
              let notation = "";
              while (i2 < xmlData.length && xmlData[i2] !== "|" && xmlData[i2] !== ")") {
                notation += xmlData[i2];
                i2++;
              }
              notation = notation.trim();
              if (!validateEntityName(notation)) {
                throw new Error(`Invalid notation name: "${notation}"`);
              }
              allowedNotations.push(notation);
              if (xmlData[i2] === "|") {
                i2++;
                i2 = skipWhitespace(xmlData, i2);
              }
            }
            if (xmlData[i2] !== ")") {
              throw new Error("Unterminated list of notations");
            }
            i2++;
            attributeType += " (" + allowedNotations.join("|") + ")";
          } else {
            while (i2 < xmlData.length && !/\s/.test(xmlData[i2])) {
              attributeType += xmlData[i2];
              i2++;
            }
            const validTypes = ["CDATA", "ID", "IDREF", "IDREFS", "ENTITY", "ENTITIES", "NMTOKEN", "NMTOKENS"];
            if (!this.suppressValidationErr && !validTypes.includes(attributeType.toUpperCase())) {
              throw new Error(`Invalid attribute type: "${attributeType}"`);
            }
          }
          i2 = skipWhitespace(xmlData, i2);
          let defaultValue = "";
          if (xmlData.substring(i2, i2 + 8).toUpperCase() === "#REQUIRED") {
            defaultValue = "#REQUIRED";
            i2 += 8;
          } else if (xmlData.substring(i2, i2 + 7).toUpperCase() === "#IMPLIED") {
            defaultValue = "#IMPLIED";
            i2 += 7;
          } else {
            [i2, defaultValue] = this.readIdentifierVal(xmlData, i2, "ATTLIST");
          }
          return {
            elementName,
            attributeName,
            attributeType,
            defaultValue,
            index: i2
          };
        }
      };
      var skipWhitespace = (data, index) => {
        while (index < data.length && /\s/.test(data[index])) {
          index++;
        }
        return index;
      };
      function hasSeq(data, seq, i2) {
        for (let j = 0; j < seq.length; j++) {
          if (seq[j] !== data[i2 + j + 1]) return false;
        }
        return true;
      }
      function validateEntityName(name) {
        if (util.isName(name))
          return name;
        else
          throw new Error(`Invalid entity name ${name}`);
      }
      module.exports = DocTypeReader;
    }
  });

  // node_modules/strnum/strnum.js
  var require_strnum = __commonJS({
    "node_modules/strnum/strnum.js"(exports, module) {
      var hexRegex = /^[-+]?0x[a-fA-F0-9]+$/;
      var numRegex = /^([\-\+])?(0*)([0-9]*(\.[0-9]*)?)$/;
      var consider = {
        hex: true,
        // oct: false,
        leadingZeros: true,
        decimalPoint: ".",
        eNotation: true
        //skipLike: /regex/
      };
      function toNumber(str, options = {}) {
        options = Object.assign({}, consider, options);
        if (!str || typeof str !== "string") return str;
        let trimmedStr = str.trim();
        if (options.skipLike !== void 0 && options.skipLike.test(trimmedStr)) return str;
        else if (str === "0") return 0;
        else if (options.hex && hexRegex.test(trimmedStr)) {
          return parse_int(trimmedStr, 16);
        } else if (trimmedStr.search(/[eE]/) !== -1) {
          const notation = trimmedStr.match(/^([-\+])?(0*)([0-9]*(\.[0-9]*)?[eE][-\+]?[0-9]+)$/);
          if (notation) {
            if (options.leadingZeros) {
              trimmedStr = (notation[1] || "") + notation[3];
            } else {
              if (notation[2] === "0" && notation[3][0] === ".") {
              } else {
                return str;
              }
            }
            return options.eNotation ? Number(trimmedStr) : str;
          } else {
            return str;
          }
        } else {
          const match = numRegex.exec(trimmedStr);
          if (match) {
            const sign = match[1];
            const leadingZeros = match[2];
            let numTrimmedByZeros = trimZeros(match[3]);
            if (!options.leadingZeros && leadingZeros.length > 0 && sign && trimmedStr[2] !== ".") return str;
            else if (!options.leadingZeros && leadingZeros.length > 0 && !sign && trimmedStr[1] !== ".") return str;
            else if (options.leadingZeros && leadingZeros === str) return 0;
            else {
              const num = Number(trimmedStr);
              const numStr = "" + num;
              if (numStr.search(/[eE]/) !== -1) {
                if (options.eNotation) return num;
                else return str;
              } else if (trimmedStr.indexOf(".") !== -1) {
                if (numStr === "0" && numTrimmedByZeros === "") return num;
                else if (numStr === numTrimmedByZeros) return num;
                else if (sign && numStr === "-" + numTrimmedByZeros) return num;
                else return str;
              }
              if (leadingZeros) {
                return numTrimmedByZeros === numStr || sign + numTrimmedByZeros === numStr ? num : str;
              } else {
                return trimmedStr === numStr || trimmedStr === sign + numStr ? num : str;
              }
            }
          } else {
            return str;
          }
        }
      }
      function trimZeros(numStr) {
        if (numStr && numStr.indexOf(".") !== -1) {
          numStr = numStr.replace(/0+$/, "");
          if (numStr === ".") numStr = "0";
          else if (numStr[0] === ".") numStr = "0" + numStr;
          else if (numStr[numStr.length - 1] === ".") numStr = numStr.substr(0, numStr.length - 1);
          return numStr;
        }
        return numStr;
      }
      function parse_int(numStr, base) {
        if (parseInt) return parseInt(numStr, base);
        else if (Number.parseInt) return Number.parseInt(numStr, base);
        else if (window && window.parseInt) return window.parseInt(numStr, base);
        else throw new Error("parseInt, Number.parseInt, window.parseInt are not supported");
      }
      module.exports = toNumber;
    }
  });

  // node_modules/fast-xml-parser/src/ignoreAttributes.js
  var require_ignoreAttributes = __commonJS({
    "node_modules/fast-xml-parser/src/ignoreAttributes.js"(exports, module) {
      function getIgnoreAttributesFn(ignoreAttributes) {
        if (typeof ignoreAttributes === "function") {
          return ignoreAttributes;
        }
        if (Array.isArray(ignoreAttributes)) {
          return (attrName) => {
            for (const pattern of ignoreAttributes) {
              if (typeof pattern === "string" && attrName === pattern) {
                return true;
              }
              if (pattern instanceof RegExp && pattern.test(attrName)) {
                return true;
              }
            }
          };
        }
        return () => false;
      }
      module.exports = getIgnoreAttributesFn;
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/OrderedObjParser.js
  var require_OrderedObjParser = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/OrderedObjParser.js"(exports, module) {
      "use strict";
      var util = require_util();
      var xmlNode = require_xmlNode();
      var DocTypeReader = require_DocTypeReader();
      var toNumber = require_strnum();
      var getIgnoreAttributesFn = require_ignoreAttributes();
      var OrderedObjParser = class {
        constructor(options) {
          this.options = options;
          this.currentNode = null;
          this.tagsNodeStack = [];
          this.docTypeEntities = {};
          this.lastEntities = {
            "apos": { regex: /&(apos|#39|#x27);/g, val: "'" },
            "gt": { regex: /&(gt|#62|#x3E);/g, val: ">" },
            "lt": { regex: /&(lt|#60|#x3C);/g, val: "<" },
            "quot": { regex: /&(quot|#34|#x22);/g, val: '"' }
          };
          this.ampEntity = { regex: /&(amp|#38|#x26);/g, val: "&" };
          this.htmlEntities = {
            "space": { regex: /&(nbsp|#160);/g, val: " " },
            // "lt" : { regex: /&(lt|#60);/g, val: "<" },
            // "gt" : { regex: /&(gt|#62);/g, val: ">" },
            // "amp" : { regex: /&(amp|#38);/g, val: "&" },
            // "quot" : { regex: /&(quot|#34);/g, val: "\"" },
            // "apos" : { regex: /&(apos|#39);/g, val: "'" },
            "cent": { regex: /&(cent|#162);/g, val: "\xA2" },
            "pound": { regex: /&(pound|#163);/g, val: "\xA3" },
            "yen": { regex: /&(yen|#165);/g, val: "\xA5" },
            "euro": { regex: /&(euro|#8364);/g, val: "\u20AC" },
            "copyright": { regex: /&(copy|#169);/g, val: "\xA9" },
            "reg": { regex: /&(reg|#174);/g, val: "\xAE" },
            "inr": { regex: /&(inr|#8377);/g, val: "\u20B9" },
            "num_dec": { regex: /&#([0-9]{1,7});/g, val: (_, str) => fromCodePoint(str, 10, "&#") },
            "num_hex": { regex: /&#x([0-9a-fA-F]{1,6});/g, val: (_, str) => fromCodePoint(str, 16, "&#x") }
          };
          this.addExternalEntities = addExternalEntities;
          this.parseXml = parseXml;
          this.parseTextData = parseTextData;
          this.resolveNameSpace = resolveNameSpace;
          this.buildAttributesMap = buildAttributesMap;
          this.isItStopNode = isItStopNode;
          this.replaceEntitiesValue = replaceEntitiesValue;
          this.readStopNodeData = readStopNodeData;
          this.saveTextToParentTag = saveTextToParentTag;
          this.addChild = addChild;
          this.ignoreAttributesFn = getIgnoreAttributesFn(this.options.ignoreAttributes);
          this.entityExpansionCount = 0;
          this.currentExpandedLength = 0;
          if (this.options.stopNodes && this.options.stopNodes.length > 0) {
            this.stopNodesExact = /* @__PURE__ */ new Set();
            this.stopNodesWildcard = /* @__PURE__ */ new Set();
            for (let i2 = 0; i2 < this.options.stopNodes.length; i2++) {
              const stopNodeExp = this.options.stopNodes[i2];
              if (typeof stopNodeExp !== "string") continue;
              if (stopNodeExp.startsWith("*.")) {
                this.stopNodesWildcard.add(stopNodeExp.substring(2));
              } else {
                this.stopNodesExact.add(stopNodeExp);
              }
            }
          }
        }
      };
      function addExternalEntities(externalEntities) {
        const entKeys = Object.keys(externalEntities);
        for (let i2 = 0; i2 < entKeys.length; i2++) {
          const ent = entKeys[i2];
          const escaped = ent.replace(/[.\-+*:]/g, "\\.");
          this.lastEntities[ent] = {
            regex: new RegExp("&" + escaped + ";", "g"),
            val: externalEntities[ent]
          };
        }
      }
      function parseTextData(val, tagName, jPath, dontTrim, hasAttributes, isLeafNode, escapeEntities) {
        if (val !== void 0) {
          if (this.options.trimValues && !dontTrim) {
            val = val.trim();
          }
          if (val.length > 0) {
            if (!escapeEntities) val = this.replaceEntitiesValue(val, tagName, jPath);
            const newval = this.options.tagValueProcessor(tagName, val, jPath, hasAttributes, isLeafNode);
            if (newval === null || newval === void 0) {
              return val;
            } else if (typeof newval !== typeof val || newval !== val) {
              return newval;
            } else if (this.options.trimValues) {
              return parseValue(val, this.options.parseTagValue, this.options.numberParseOptions);
            } else {
              const trimmedVal = val.trim();
              if (trimmedVal === val) {
                return parseValue(val, this.options.parseTagValue, this.options.numberParseOptions);
              } else {
                return val;
              }
            }
          }
        }
      }
      function resolveNameSpace(tagname) {
        if (this.options.removeNSPrefix) {
          const tags = tagname.split(":");
          const prefix = tagname.charAt(0) === "/" ? "/" : "";
          if (tags[0] === "xmlns") {
            return "";
          }
          if (tags.length === 2) {
            tagname = prefix + tags[1];
          }
        }
        return tagname;
      }
      var attrsRegx = new RegExp(`([^\\s=]+)\\s*(=\\s*(['"])([\\s\\S]*?)\\3)?`, "gm");
      function buildAttributesMap(attrStr, jPath, tagName) {
        if (this.options.ignoreAttributes !== true && typeof attrStr === "string") {
          const matches = util.getAllMatches(attrStr, attrsRegx);
          const len = matches.length;
          const attrs = {};
          for (let i2 = 0; i2 < len; i2++) {
            const attrName = this.resolveNameSpace(matches[i2][1]);
            if (this.ignoreAttributesFn(attrName, jPath)) {
              continue;
            }
            let oldVal = matches[i2][4];
            let aName = this.options.attributeNamePrefix + attrName;
            if (attrName.length) {
              if (this.options.transformAttributeName) {
                aName = this.options.transformAttributeName(aName);
              }
              aName = sanitizeName(aName, this.options);
              if (oldVal !== void 0) {
                if (this.options.trimValues) {
                  oldVal = oldVal.trim();
                }
                oldVal = this.replaceEntitiesValue(oldVal, tagName, jPath);
                const newVal = this.options.attributeValueProcessor(attrName, oldVal, jPath);
                if (newVal === null || newVal === void 0) {
                  attrs[aName] = oldVal;
                } else if (typeof newVal !== typeof oldVal || newVal !== oldVal) {
                  attrs[aName] = newVal;
                } else {
                  attrs[aName] = parseValue(
                    oldVal,
                    this.options.parseAttributeValue,
                    this.options.numberParseOptions
                  );
                }
              } else if (this.options.allowBooleanAttributes) {
                attrs[aName] = true;
              }
            }
          }
          if (!Object.keys(attrs).length) {
            return;
          }
          if (this.options.attributesGroupName) {
            const attrCollection = {};
            attrCollection[this.options.attributesGroupName] = attrs;
            return attrCollection;
          }
          return attrs;
        }
      }
      var parseXml = function(xmlData) {
        xmlData = xmlData.replace(/\r\n?/g, "\n");
        const xmlObj = new xmlNode("!xml");
        let currentNode = xmlObj;
        let textData = "";
        let jPath = "";
        this.entityExpansionCount = 0;
        this.currentExpandedLength = 0;
        const docTypeReader = new DocTypeReader(this.options.processEntities);
        for (let i2 = 0; i2 < xmlData.length; i2++) {
          const ch = xmlData[i2];
          if (ch === "<") {
            if (xmlData[i2 + 1] === "/") {
              const closeIndex = findClosingIndex(xmlData, ">", i2, "Closing Tag is not closed.");
              let tagName = xmlData.substring(i2 + 2, closeIndex).trim();
              if (this.options.removeNSPrefix) {
                const colonIndex = tagName.indexOf(":");
                if (colonIndex !== -1) {
                  tagName = tagName.substr(colonIndex + 1);
                }
              }
              if (this.options.transformTagName) {
                tagName = this.options.transformTagName(tagName);
              }
              if (currentNode) {
                textData = this.saveTextToParentTag(textData, currentNode, jPath);
              }
              const lastTagName = jPath.substring(jPath.lastIndexOf(".") + 1);
              if (tagName && this.options.unpairedTags.indexOf(tagName) !== -1) {
                throw new Error(`Unpaired tag can not be used as closing tag: </${tagName}>`);
              }
              let propIndex = 0;
              if (lastTagName && this.options.unpairedTags.indexOf(lastTagName) !== -1) {
                propIndex = jPath.lastIndexOf(".", jPath.lastIndexOf(".") - 1);
                this.tagsNodeStack.pop();
              } else {
                propIndex = jPath.lastIndexOf(".");
              }
              jPath = jPath.substring(0, propIndex);
              currentNode = this.tagsNodeStack.pop();
              textData = "";
              i2 = closeIndex;
            } else if (xmlData[i2 + 1] === "?") {
              let tagData = readTagExp(xmlData, i2, false, "?>");
              if (!tagData) throw new Error("Pi Tag is not closed.");
              textData = this.saveTextToParentTag(textData, currentNode, jPath);
              if (this.options.ignoreDeclaration && tagData.tagName === "?xml" || this.options.ignorePiTags) {
              } else {
                const childNode = new xmlNode(tagData.tagName);
                childNode.add(this.options.textNodeName, "");
                if (tagData.tagName !== tagData.tagExp && tagData.attrExpPresent) {
                  childNode[":@"] = this.buildAttributesMap(tagData.tagExp, jPath, tagData.tagName);
                }
                this.addChild(currentNode, childNode, jPath, i2);
              }
              i2 = tagData.closeIndex + 1;
            } else if (xmlData.substr(i2 + 1, 3) === "!--") {
              const endIndex = findClosingIndex(xmlData, "-->", i2 + 4, "Comment is not closed.");
              if (this.options.commentPropName) {
                const comment = xmlData.substring(i2 + 4, endIndex - 2);
                textData = this.saveTextToParentTag(textData, currentNode, jPath);
                currentNode.add(this.options.commentPropName, [{ [this.options.textNodeName]: comment }]);
              }
              i2 = endIndex;
            } else if (xmlData.substr(i2 + 1, 2) === "!D") {
              const result = docTypeReader.readDocType(xmlData, i2);
              this.docTypeEntities = result.entities;
              i2 = result.i;
            } else if (xmlData.substr(i2 + 1, 2) === "![") {
              const closeIndex = findClosingIndex(xmlData, "]]>", i2, "CDATA is not closed.") - 2;
              const tagExp = xmlData.substring(i2 + 9, closeIndex);
              textData = this.saveTextToParentTag(textData, currentNode, jPath);
              let val = this.parseTextData(tagExp, currentNode.tagname, jPath, true, false, true, true);
              if (val == void 0) val = "";
              if (this.options.cdataPropName) {
                currentNode.add(this.options.cdataPropName, [{ [this.options.textNodeName]: tagExp }]);
              } else {
                currentNode.add(this.options.textNodeName, val);
              }
              i2 = closeIndex + 2;
            } else {
              let result = readTagExp(xmlData, i2, this.options.removeNSPrefix);
              let tagName = result.tagName;
              const rawTagName = result.rawTagName;
              let tagExp = result.tagExp;
              let attrExpPresent = result.attrExpPresent;
              let closeIndex = result.closeIndex;
              if (this.options.transformTagName) {
                const newTagName = this.options.transformTagName(tagName);
                if (tagExp === tagName) {
                  tagExp = newTagName;
                }
                tagName = newTagName;
              }
              if (this.options.strictReservedNames && (tagName === this.options.commentPropName || tagName === this.options.cdataPropName || tagName === this.options.textNodeName || tagName === this.options.attributesGroupName)) {
                throw new Error(`Invalid tag name: ${tagName}`);
              }
              if (currentNode && textData) {
                if (currentNode.tagname !== "!xml") {
                  textData = this.saveTextToParentTag(textData, currentNode, jPath, false);
                }
              }
              const lastTag = currentNode;
              if (lastTag && this.options.unpairedTags.indexOf(lastTag.tagname) !== -1) {
                currentNode = this.tagsNodeStack.pop();
                jPath = jPath.substring(0, jPath.lastIndexOf("."));
              }
              if (tagName !== xmlObj.tagname) {
                jPath += jPath ? "." + tagName : tagName;
              }
              const startIndex = i2;
              if (this.isItStopNode(this.stopNodesExact, this.stopNodesWildcard, jPath, tagName)) {
                let tagContent = "";
                if (tagExp.length > 0 && tagExp.lastIndexOf("/") === tagExp.length - 1) {
                  if (tagName[tagName.length - 1] === "/") {
                    tagName = tagName.substr(0, tagName.length - 1);
                    jPath = jPath.substr(0, jPath.length - 1);
                    tagExp = tagName;
                  } else {
                    tagExp = tagExp.substr(0, tagExp.length - 1);
                  }
                  i2 = result.closeIndex;
                } else if (this.options.unpairedTags.indexOf(tagName) !== -1) {
                  i2 = result.closeIndex;
                } else {
                  const result2 = this.readStopNodeData(xmlData, rawTagName, closeIndex + 1);
                  if (!result2) throw new Error(`Unexpected end of ${rawTagName}`);
                  i2 = result2.i;
                  tagContent = result2.tagContent;
                }
                const childNode = new xmlNode(tagName);
                if (tagName !== tagExp && attrExpPresent) {
                  childNode[":@"] = this.buildAttributesMap(tagExp, jPath, tagName);
                }
                if (tagContent) {
                  tagContent = this.parseTextData(tagContent, tagName, jPath, true, attrExpPresent, true, true);
                }
                jPath = jPath.substr(0, jPath.lastIndexOf("."));
                childNode.add(this.options.textNodeName, tagContent);
                this.addChild(currentNode, childNode, jPath, startIndex);
              } else {
                if (tagExp.length > 0 && tagExp.lastIndexOf("/") === tagExp.length - 1) {
                  if (tagName[tagName.length - 1] === "/") {
                    tagName = tagName.substr(0, tagName.length - 1);
                    jPath = jPath.substr(0, jPath.length - 1);
                    tagExp = tagName;
                  } else {
                    tagExp = tagExp.substr(0, tagExp.length - 1);
                  }
                  if (this.options.transformTagName) {
                    const newTagName = this.options.transformTagName(tagName);
                    if (tagExp === tagName) {
                      tagExp = newTagName;
                    }
                    tagName = newTagName;
                  }
                  const childNode = new xmlNode(tagName);
                  if (tagName !== tagExp && attrExpPresent) {
                    childNode[":@"] = this.buildAttributesMap(tagExp, jPath, tagName);
                  }
                  this.addChild(currentNode, childNode, jPath, startIndex);
                  jPath = jPath.substr(0, jPath.lastIndexOf("."));
                } else if (this.options.unpairedTags.indexOf(tagName) !== -1) {
                  const childNode = new xmlNode(tagName);
                  if (tagName !== tagExp && attrExpPresent) {
                    childNode[":@"] = this.buildAttributesMap(tagExp, jPath);
                  }
                  this.addChild(currentNode, childNode, jPath, startIndex);
                  jPath = jPath.substr(0, jPath.lastIndexOf("."));
                  i2 = result.closeIndex;
                  continue;
                } else {
                  const childNode = new xmlNode(tagName);
                  if (this.tagsNodeStack.length > this.options.maxNestedTags) {
                    throw new Error("Maximum nested tags exceeded");
                  }
                  this.tagsNodeStack.push(currentNode);
                  if (tagName !== tagExp && attrExpPresent) {
                    childNode[":@"] = this.buildAttributesMap(tagExp, jPath, tagName);
                  }
                  this.addChild(currentNode, childNode, jPath);
                  currentNode = childNode;
                }
                textData = "";
                i2 = closeIndex;
              }
            }
          } else {
            textData += xmlData[i2];
          }
        }
        return xmlObj.child;
      };
      function addChild(currentNode, childNode, jPath, startIndex) {
        if (!this.options.captureMetaData) startIndex = void 0;
        const result = this.options.updateTag(childNode.tagname, jPath, childNode[":@"]);
        if (result === false) {
        } else if (typeof result === "string") {
          childNode.tagname = result;
          currentNode.addChild(childNode, startIndex);
        } else {
          currentNode.addChild(childNode, startIndex);
        }
      }
      var replaceEntitiesValue = function(val, tagName, jPath) {
        if (val.indexOf("&") === -1) {
          return val;
        }
        const entityConfig = this.options.processEntities;
        if (!entityConfig.enabled) {
          return val;
        }
        if (entityConfig.allowedTags) {
          if (!entityConfig.allowedTags.includes(tagName)) {
            return val;
          }
        }
        if (entityConfig.tagFilter) {
          if (!entityConfig.tagFilter(tagName, jPath)) {
            return val;
          }
        }
        for (let entityName in this.docTypeEntities) {
          const entity = this.docTypeEntities[entityName];
          const matches = val.match(entity.regx);
          if (matches) {
            this.entityExpansionCount += matches.length;
            if (entityConfig.maxTotalExpansions && this.entityExpansionCount > entityConfig.maxTotalExpansions) {
              throw new Error(
                `Entity expansion limit exceeded: ${this.entityExpansionCount} > ${entityConfig.maxTotalExpansions}`
              );
            }
            const lengthBefore = val.length;
            val = val.replace(entity.regx, entity.val);
            if (entityConfig.maxExpandedLength) {
              this.currentExpandedLength += val.length - lengthBefore;
              if (this.currentExpandedLength > entityConfig.maxExpandedLength) {
                throw new Error(
                  `Total expanded content size exceeded: ${this.currentExpandedLength} > ${entityConfig.maxExpandedLength}`
                );
              }
            }
          }
        }
        if (val.indexOf("&") === -1) return val;
        for (const entityName of Object.keys(this.lastEntities)) {
          const entity = this.lastEntities[entityName];
          const matches = val.match(entity.regex);
          if (matches) {
            this.entityExpansionCount += matches.length;
            if (entityConfig.maxTotalExpansions && this.entityExpansionCount > entityConfig.maxTotalExpansions) {
              throw new Error(
                `Entity expansion limit exceeded: ${this.entityExpansionCount} > ${entityConfig.maxTotalExpansions}`
              );
            }
          }
          val = val.replace(entity.regex, entity.val);
        }
        if (val.indexOf("&") === -1) return val;
        if (this.options.htmlEntities) {
          for (const entityName of Object.keys(this.htmlEntities)) {
            const entity = this.htmlEntities[entityName];
            const matches = val.match(entity.regex);
            if (matches) {
              this.entityExpansionCount += matches.length;
              if (entityConfig.maxTotalExpansions && this.entityExpansionCount > entityConfig.maxTotalExpansions) {
                throw new Error(
                  `Entity expansion limit exceeded: ${this.entityExpansionCount} > ${entityConfig.maxTotalExpansions}`
                );
              }
            }
            val = val.replace(entity.regex, entity.val);
          }
        }
        val = val.replace(this.ampEntity.regex, this.ampEntity.val);
        return val;
      };
      function saveTextToParentTag(textData, parentNode, jPath, isLeafNode) {
        if (textData) {
          if (isLeafNode === void 0) isLeafNode = parentNode.child.length === 0;
          textData = this.parseTextData(
            textData,
            parentNode.tagname,
            jPath,
            false,
            parentNode[":@"] ? Object.keys(parentNode[":@"]).length !== 0 : false,
            isLeafNode
          );
          if (textData !== void 0 && textData !== "")
            parentNode.add(this.options.textNodeName, textData);
          textData = "";
        }
        return textData;
      }
      function isItStopNode(stopNodesExact, stopNodesWildcard, jPath, currentTagName) {
        if (stopNodesWildcard && stopNodesWildcard.has(currentTagName)) return true;
        if (stopNodesExact && stopNodesExact.has(jPath)) return true;
        return false;
      }
      function tagExpWithClosingIndex(xmlData, i2, closingChar = ">") {
        let attrBoundary;
        let tagExp = "";
        for (let index = i2; index < xmlData.length; index++) {
          let ch = xmlData[index];
          if (attrBoundary) {
            if (ch === attrBoundary) attrBoundary = "";
          } else if (ch === '"' || ch === "'") {
            attrBoundary = ch;
          } else if (ch === closingChar[0]) {
            if (closingChar[1]) {
              if (xmlData[index + 1] === closingChar[1]) {
                return {
                  data: tagExp,
                  index
                };
              }
            } else {
              return {
                data: tagExp,
                index
              };
            }
          } else if (ch === "	") {
            ch = " ";
          }
          tagExp += ch;
        }
      }
      function findClosingIndex(xmlData, str, i2, errMsg) {
        const closingIndex = xmlData.indexOf(str, i2);
        if (closingIndex === -1) {
          throw new Error(errMsg);
        } else {
          return closingIndex + str.length - 1;
        }
      }
      function readTagExp(xmlData, i2, removeNSPrefix, closingChar = ">") {
        const result = tagExpWithClosingIndex(xmlData, i2 + 1, closingChar);
        if (!result) return;
        let tagExp = result.data;
        const closeIndex = result.index;
        const separatorIndex = tagExp.search(/\s/);
        let tagName = tagExp;
        let attrExpPresent = true;
        if (separatorIndex !== -1) {
          tagName = tagExp.substring(0, separatorIndex);
          tagExp = tagExp.substring(separatorIndex + 1).trimStart();
        }
        const rawTagName = tagName;
        if (removeNSPrefix) {
          const colonIndex = tagName.indexOf(":");
          if (colonIndex !== -1) {
            tagName = tagName.substr(colonIndex + 1);
            attrExpPresent = tagName !== result.data.substr(colonIndex + 1);
          }
        }
        return {
          tagName,
          tagExp,
          closeIndex,
          attrExpPresent,
          rawTagName
        };
      }
      function readStopNodeData(xmlData, tagName, i2) {
        const startIndex = i2;
        let openTagCount = 1;
        for (; i2 < xmlData.length; i2++) {
          if (xmlData[i2] === "<") {
            if (xmlData[i2 + 1] === "/") {
              const closeIndex = findClosingIndex(xmlData, ">", i2, `${tagName} is not closed`);
              let closeTagName = xmlData.substring(i2 + 2, closeIndex).trim();
              if (closeTagName === tagName) {
                openTagCount--;
                if (openTagCount === 0) {
                  return {
                    tagContent: xmlData.substring(startIndex, i2),
                    i: closeIndex
                  };
                }
              }
              i2 = closeIndex;
            } else if (xmlData[i2 + 1] === "?") {
              const closeIndex = findClosingIndex(xmlData, "?>", i2 + 1, "StopNode is not closed.");
              i2 = closeIndex;
            } else if (xmlData.substr(i2 + 1, 3) === "!--") {
              const closeIndex = findClosingIndex(xmlData, "-->", i2 + 3, "StopNode is not closed.");
              i2 = closeIndex;
            } else if (xmlData.substr(i2 + 1, 2) === "![") {
              const closeIndex = findClosingIndex(xmlData, "]]>", i2, "StopNode is not closed.") - 2;
              i2 = closeIndex;
            } else {
              const tagData = readTagExp(xmlData, i2, ">");
              if (tagData) {
                const openTagName = tagData && tagData.tagName;
                if (openTagName === tagName && tagData.tagExp[tagData.tagExp.length - 1] !== "/") {
                  openTagCount++;
                }
                i2 = tagData.closeIndex;
              }
            }
          }
        }
      }
      function parseValue(val, shouldParse, options) {
        if (shouldParse && typeof val === "string") {
          const newval = val.trim();
          if (newval === "true") return true;
          else if (newval === "false") return false;
          else return toNumber(val, options);
        } else {
          if (util.isExist(val)) {
            return val;
          } else {
            return "";
          }
        }
      }
      function fromCodePoint(str, base, prefix) {
        const codePoint = Number.parseInt(str, base);
        if (codePoint >= 0 && codePoint <= 1114111) {
          return String.fromCodePoint(codePoint);
        } else {
          return prefix + str + ";";
        }
      }
      function sanitizeName(name, options) {
        if (util.criticalProperties.includes(name)) {
          throw new Error(`[SECURITY] Invalid name: "${name}" is a reserved JavaScript keyword that could cause prototype pollution`);
        } else if (util.DANGEROUS_PROPERTY_NAMES.includes(name)) {
          return options.onDangerousProperty(name);
        }
        return name;
      }
      module.exports = OrderedObjParser;
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/node2json.js
  var require_node2json = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/node2json.js"(exports) {
      "use strict";
      function prettify(node2, options) {
        return compress(node2, options);
      }
      function compress(arr4, options, jPath) {
        let text3;
        const compressedObj = {};
        for (let i2 = 0; i2 < arr4.length; i2++) {
          const tagObj = arr4[i2];
          const property = propName(tagObj);
          let newJpath = "";
          if (jPath === void 0) newJpath = property;
          else newJpath = jPath + "." + property;
          if (property === options.textNodeName) {
            if (text3 === void 0) text3 = tagObj[property];
            else text3 += "" + tagObj[property];
          } else if (property === void 0) {
            continue;
          } else if (tagObj[property]) {
            let val = compress(tagObj[property], options, newJpath);
            const isLeaf = isLeafTag(val, options);
            if (tagObj[":@"]) {
              assignAttributes(val, tagObj[":@"], newJpath, options);
            } else if (Object.keys(val).length === 1 && val[options.textNodeName] !== void 0 && !options.alwaysCreateTextNode) {
              val = val[options.textNodeName];
            } else if (Object.keys(val).length === 0) {
              if (options.alwaysCreateTextNode) val[options.textNodeName] = "";
              else val = "";
            }
            if (compressedObj[property] !== void 0 && compressedObj.hasOwnProperty(property)) {
              if (!Array.isArray(compressedObj[property])) {
                compressedObj[property] = [compressedObj[property]];
              }
              compressedObj[property].push(val);
            } else {
              if (options.isArray(property, newJpath, isLeaf)) {
                compressedObj[property] = [val];
              } else {
                compressedObj[property] = val;
              }
            }
          }
        }
        if (typeof text3 === "string") {
          if (text3.length > 0) compressedObj[options.textNodeName] = text3;
        } else if (text3 !== void 0) compressedObj[options.textNodeName] = text3;
        return compressedObj;
      }
      function propName(obj) {
        const keys = Object.keys(obj);
        for (let i2 = 0; i2 < keys.length; i2++) {
          const key = keys[i2];
          if (key !== ":@") return key;
        }
      }
      function assignAttributes(obj, attrMap, jpath, options) {
        if (attrMap) {
          const keys = Object.keys(attrMap);
          const len = keys.length;
          for (let i2 = 0; i2 < len; i2++) {
            const atrrName = keys[i2];
            if (options.isArray(atrrName, jpath + "." + atrrName, true, true)) {
              obj[atrrName] = [attrMap[atrrName]];
            } else {
              obj[atrrName] = attrMap[atrrName];
            }
          }
        }
      }
      function isLeafTag(obj, options) {
        const { textNodeName } = options;
        const propCount = Object.keys(obj).length;
        if (propCount === 0) {
          return true;
        }
        if (propCount === 1 && (obj[textNodeName] || typeof obj[textNodeName] === "boolean" || obj[textNodeName] === 0)) {
          return true;
        }
        return false;
      }
      exports.prettify = prettify;
    }
  });

  // node_modules/fast-xml-parser/src/xmlparser/XMLParser.js
  var require_XMLParser = __commonJS({
    "node_modules/fast-xml-parser/src/xmlparser/XMLParser.js"(exports, module) {
      var { buildOptions } = require_OptionsBuilder();
      var OrderedObjParser = require_OrderedObjParser();
      var { prettify } = require_node2json();
      var validator = require_validator();
      var XMLParser5 = class {
        constructor(options) {
          this.externalEntities = {};
          this.options = buildOptions(options);
        }
        /**
         * Parse XML dats to JS object 
         * @param {string|Buffer} xmlData 
         * @param {boolean|Object} validationOption 
         */
        parse(xmlData, validationOption) {
          if (typeof xmlData === "string") {
          } else if (xmlData.toString) {
            xmlData = xmlData.toString();
          } else {
            throw new Error("XML data is accepted in String or Bytes[] form.");
          }
          if (validationOption) {
            if (validationOption === true) validationOption = {};
            const result = validator.validate(xmlData, validationOption);
            if (result !== true) {
              throw Error(`${result.err.msg}:${result.err.line}:${result.err.col}`);
            }
          }
          const orderedObjParser = new OrderedObjParser(this.options);
          orderedObjParser.addExternalEntities(this.externalEntities);
          const orderedResult = orderedObjParser.parseXml(xmlData);
          if (this.options.preserveOrder || orderedResult === void 0) return orderedResult;
          else return prettify(orderedResult, this.options);
        }
        /**
         * Add Entity which is not by default supported by this library
         * @param {string} key 
         * @param {string} value 
         */
        addEntity(key, value) {
          if (value.indexOf("&") !== -1) {
            throw new Error("Entity value can't have '&'");
          } else if (key.indexOf("&") !== -1 || key.indexOf(";") !== -1) {
            throw new Error("An entity must be set without '&' and ';'. Eg. use '#xD' for '&#xD;'");
          } else if (value === "&") {
            throw new Error("An entity with value '&' is not permitted");
          } else {
            this.externalEntities[key] = value;
          }
        }
      };
      module.exports = XMLParser5;
    }
  });

  // node_modules/fast-xml-parser/src/xmlbuilder/orderedJs2Xml.js
  var require_orderedJs2Xml = __commonJS({
    "node_modules/fast-xml-parser/src/xmlbuilder/orderedJs2Xml.js"(exports, module) {
      var EOL = "\n";
      function toXml(jArray, options) {
        let indentation = "";
        if (options.format && options.indentBy.length > 0) {
          indentation = EOL;
        }
        return arrToStr(jArray, options, "", indentation);
      }
      function arrToStr(arr4, options, jPath, indentation) {
        let xmlStr = "";
        let isPreviousElementTag = false;
        if (!Array.isArray(arr4)) {
          if (arr4 !== void 0 && arr4 !== null) {
            let text3 = arr4.toString();
            text3 = replaceEntitiesValue(text3, options);
            return text3;
          }
          return "";
        }
        for (let i2 = 0; i2 < arr4.length; i2++) {
          const tagObj = arr4[i2];
          const tagName = propName(tagObj);
          if (tagName === void 0) continue;
          let newJPath = "";
          if (jPath.length === 0) newJPath = tagName;
          else newJPath = `${jPath}.${tagName}`;
          if (tagName === options.textNodeName) {
            let tagText = tagObj[tagName];
            if (!isStopNode(newJPath, options)) {
              tagText = options.tagValueProcessor(tagName, tagText);
              tagText = replaceEntitiesValue(tagText, options);
            }
            if (isPreviousElementTag) {
              xmlStr += indentation;
            }
            xmlStr += tagText;
            isPreviousElementTag = false;
            continue;
          } else if (tagName === options.cdataPropName) {
            if (isPreviousElementTag) {
              xmlStr += indentation;
            }
            xmlStr += `<![CDATA[${tagObj[tagName][0][options.textNodeName]}]]>`;
            isPreviousElementTag = false;
            continue;
          } else if (tagName === options.commentPropName) {
            xmlStr += indentation + `<!--${tagObj[tagName][0][options.textNodeName]}-->`;
            isPreviousElementTag = true;
            continue;
          } else if (tagName[0] === "?") {
            const attStr2 = attr_to_str(tagObj[":@"], options);
            const tempInd = tagName === "?xml" ? "" : indentation;
            let piTextNodeName = tagObj[tagName][0][options.textNodeName];
            piTextNodeName = piTextNodeName.length !== 0 ? " " + piTextNodeName : "";
            xmlStr += tempInd + `<${tagName}${piTextNodeName}${attStr2}?>`;
            isPreviousElementTag = true;
            continue;
          }
          let newIdentation = indentation;
          if (newIdentation !== "") {
            newIdentation += options.indentBy;
          }
          const attStr = attr_to_str(tagObj[":@"], options);
          const tagStart = indentation + `<${tagName}${attStr}`;
          const tagValue = arrToStr(tagObj[tagName], options, newJPath, newIdentation);
          if (options.unpairedTags.indexOf(tagName) !== -1) {
            if (options.suppressUnpairedNode) xmlStr += tagStart + ">";
            else xmlStr += tagStart + "/>";
          } else if ((!tagValue || tagValue.length === 0) && options.suppressEmptyNode) {
            xmlStr += tagStart + "/>";
          } else if (tagValue && tagValue.endsWith(">")) {
            xmlStr += tagStart + `>${tagValue}${indentation}</${tagName}>`;
          } else {
            xmlStr += tagStart + ">";
            if (tagValue && indentation !== "" && (tagValue.includes("/>") || tagValue.includes("</"))) {
              xmlStr += indentation + options.indentBy + tagValue + indentation;
            } else {
              xmlStr += tagValue;
            }
            xmlStr += `</${tagName}>`;
          }
          isPreviousElementTag = true;
        }
        return xmlStr;
      }
      function propName(obj) {
        const keys = Object.keys(obj);
        for (let i2 = 0; i2 < keys.length; i2++) {
          const key = keys[i2];
          if (!Object.prototype.hasOwnProperty.call(obj, key)) continue;
          if (key !== ":@") return key;
        }
      }
      function attr_to_str(attrMap, options) {
        let attrStr = "";
        if (attrMap && !options.ignoreAttributes) {
          for (let attr in attrMap) {
            if (!Object.prototype.hasOwnProperty.call(attrMap, attr)) continue;
            let attrVal = options.attributeValueProcessor(attr, attrMap[attr]);
            attrVal = replaceEntitiesValue(attrVal, options);
            if (attrVal === true && options.suppressBooleanAttributes) {
              attrStr += ` ${attr.substr(options.attributeNamePrefix.length)}`;
            } else {
              attrStr += ` ${attr.substr(options.attributeNamePrefix.length)}="${attrVal}"`;
            }
          }
        }
        return attrStr;
      }
      function isStopNode(jPath, options) {
        jPath = jPath.substr(0, jPath.length - options.textNodeName.length - 1);
        let tagName = jPath.substr(jPath.lastIndexOf(".") + 1);
        for (let index in options.stopNodes) {
          if (options.stopNodes[index] === jPath || options.stopNodes[index] === "*." + tagName) return true;
        }
        return false;
      }
      function replaceEntitiesValue(textValue, options) {
        if (textValue && textValue.length > 0 && options.processEntities) {
          for (let i2 = 0; i2 < options.entities.length; i2++) {
            const entity = options.entities[i2];
            textValue = textValue.replace(entity.regex, entity.val);
          }
        }
        return textValue;
      }
      module.exports = toXml;
    }
  });

  // node_modules/fast-xml-parser/src/xmlbuilder/json2xml.js
  var require_json2xml = __commonJS({
    "node_modules/fast-xml-parser/src/xmlbuilder/json2xml.js"(exports, module) {
      "use strict";
      var buildFromOrderedJs = require_orderedJs2Xml();
      var getIgnoreAttributesFn = require_ignoreAttributes();
      var defaultOptions = {
        attributeNamePrefix: "@_",
        attributesGroupName: false,
        textNodeName: "#text",
        ignoreAttributes: true,
        cdataPropName: false,
        format: false,
        indentBy: "  ",
        suppressEmptyNode: false,
        suppressUnpairedNode: true,
        suppressBooleanAttributes: true,
        tagValueProcessor: function(key, a) {
          return a;
        },
        attributeValueProcessor: function(attrName, a) {
          return a;
        },
        preserveOrder: false,
        commentPropName: false,
        unpairedTags: [],
        entities: [
          { regex: new RegExp("&", "g"), val: "&amp;" },
          //it must be on top
          { regex: new RegExp(">", "g"), val: "&gt;" },
          { regex: new RegExp("<", "g"), val: "&lt;" },
          { regex: new RegExp("'", "g"), val: "&apos;" },
          { regex: new RegExp('"', "g"), val: "&quot;" }
        ],
        processEntities: true,
        stopNodes: [],
        // transformTagName: false,
        // transformAttributeName: false,
        oneListGroup: false
      };
      function Builder(options) {
        this.options = Object.assign({}, defaultOptions, options);
        if (this.options.ignoreAttributes === true || this.options.attributesGroupName) {
          this.isAttribute = function() {
            return false;
          };
        } else {
          this.ignoreAttributesFn = getIgnoreAttributesFn(this.options.ignoreAttributes);
          this.attrPrefixLen = this.options.attributeNamePrefix.length;
          this.isAttribute = isAttribute;
        }
        this.processTextOrObjNode = processTextOrObjNode;
        if (this.options.format) {
          this.indentate = indentate;
          this.tagEndChar = ">\n";
          this.newLine = "\n";
        } else {
          this.indentate = function() {
            return "";
          };
          this.tagEndChar = ">";
          this.newLine = "";
        }
      }
      Builder.prototype.build = function(jObj) {
        if (this.options.preserveOrder) {
          return buildFromOrderedJs(jObj, this.options);
        } else {
          if (Array.isArray(jObj) && this.options.arrayNodeName && this.options.arrayNodeName.length > 1) {
            jObj = {
              [this.options.arrayNodeName]: jObj
            };
          }
          return this.j2x(jObj, 0, []).val;
        }
      };
      Builder.prototype.j2x = function(jObj, level, ajPath) {
        let attrStr = "";
        let val = "";
        const jPath = ajPath.join(".");
        for (let key in jObj) {
          if (!Object.prototype.hasOwnProperty.call(jObj, key)) continue;
          if (typeof jObj[key] === "undefined") {
            if (this.isAttribute(key)) {
              val += "";
            }
          } else if (jObj[key] === null) {
            if (this.isAttribute(key)) {
              val += "";
            } else if (key === this.options.cdataPropName) {
              val += "";
            } else if (key[0] === "?") {
              val += this.indentate(level) + "<" + key + "?" + this.tagEndChar;
            } else {
              val += this.indentate(level) + "<" + key + "/" + this.tagEndChar;
            }
          } else if (jObj[key] instanceof Date) {
            val += this.buildTextValNode(jObj[key], key, "", level);
          } else if (typeof jObj[key] !== "object") {
            const attr = this.isAttribute(key);
            if (attr && !this.ignoreAttributesFn(attr, jPath)) {
              attrStr += this.buildAttrPairStr(attr, "" + jObj[key]);
            } else if (!attr) {
              if (key === this.options.textNodeName) {
                let newval = this.options.tagValueProcessor(key, "" + jObj[key]);
                val += this.replaceEntitiesValue(newval);
              } else {
                val += this.buildTextValNode(jObj[key], key, "", level);
              }
            }
          } else if (Array.isArray(jObj[key])) {
            const arrLen = jObj[key].length;
            let listTagVal = "";
            let listTagAttr = "";
            for (let j = 0; j < arrLen; j++) {
              const item = jObj[key][j];
              if (typeof item === "undefined") {
              } else if (item === null) {
                if (key[0] === "?") val += this.indentate(level) + "<" + key + "?" + this.tagEndChar;
                else val += this.indentate(level) + "<" + key + "/" + this.tagEndChar;
              } else if (typeof item === "object") {
                if (this.options.oneListGroup) {
                  const result = this.j2x(item, level + 1, ajPath.concat(key));
                  listTagVal += result.val;
                  if (this.options.attributesGroupName && item.hasOwnProperty(this.options.attributesGroupName)) {
                    listTagAttr += result.attrStr;
                  }
                } else {
                  listTagVal += this.processTextOrObjNode(item, key, level, ajPath);
                }
              } else {
                if (this.options.oneListGroup) {
                  let textValue = this.options.tagValueProcessor(key, item);
                  textValue = this.replaceEntitiesValue(textValue);
                  listTagVal += textValue;
                } else {
                  listTagVal += this.buildTextValNode(item, key, "", level);
                }
              }
            }
            if (this.options.oneListGroup) {
              listTagVal = this.buildObjectNode(listTagVal, key, listTagAttr, level);
            }
            val += listTagVal;
          } else {
            if (this.options.attributesGroupName && key === this.options.attributesGroupName) {
              const Ks = Object.keys(jObj[key]);
              const L = Ks.length;
              for (let j = 0; j < L; j++) {
                attrStr += this.buildAttrPairStr(Ks[j], "" + jObj[key][Ks[j]]);
              }
            } else {
              val += this.processTextOrObjNode(jObj[key], key, level, ajPath);
            }
          }
        }
        return { attrStr, val };
      };
      Builder.prototype.buildAttrPairStr = function(attrName, val) {
        val = this.options.attributeValueProcessor(attrName, "" + val);
        val = this.replaceEntitiesValue(val);
        if (this.options.suppressBooleanAttributes && val === "true") {
          return " " + attrName;
        } else return " " + attrName + '="' + val + '"';
      };
      function processTextOrObjNode(object, key, level, ajPath) {
        const result = this.j2x(object, level + 1, ajPath.concat(key));
        if (object[this.options.textNodeName] !== void 0 && Object.keys(object).length === 1) {
          return this.buildTextValNode(object[this.options.textNodeName], key, result.attrStr, level);
        } else {
          return this.buildObjectNode(result.val, key, result.attrStr, level);
        }
      }
      Builder.prototype.buildObjectNode = function(val, key, attrStr, level) {
        if (val === "") {
          if (key[0] === "?") return this.indentate(level) + "<" + key + attrStr + "?" + this.tagEndChar;
          else {
            return this.indentate(level) + "<" + key + attrStr + this.closeTag(key) + this.tagEndChar;
          }
        } else {
          let tagEndExp = "</" + key + this.tagEndChar;
          let piClosingChar = "";
          if (key[0] === "?") {
            piClosingChar = "?";
            tagEndExp = "";
          }
          if ((attrStr || attrStr === "") && val.indexOf("<") === -1) {
            return this.indentate(level) + "<" + key + attrStr + piClosingChar + ">" + val + tagEndExp;
          } else if (this.options.commentPropName !== false && key === this.options.commentPropName && piClosingChar.length === 0) {
            return this.indentate(level) + `<!--${val}-->` + this.newLine;
          } else {
            return this.indentate(level) + "<" + key + attrStr + piClosingChar + this.tagEndChar + val + this.indentate(level) + tagEndExp;
          }
        }
      };
      Builder.prototype.closeTag = function(key) {
        let closeTag = "";
        if (this.options.unpairedTags.indexOf(key) !== -1) {
          if (!this.options.suppressUnpairedNode) closeTag = "/";
        } else if (this.options.suppressEmptyNode) {
          closeTag = "/";
        } else {
          closeTag = `></${key}`;
        }
        return closeTag;
      };
      Builder.prototype.buildTextValNode = function(val, key, attrStr, level) {
        if (this.options.cdataPropName !== false && key === this.options.cdataPropName) {
          return this.indentate(level) + `<![CDATA[${val}]]>` + this.newLine;
        } else if (this.options.commentPropName !== false && key === this.options.commentPropName) {
          return this.indentate(level) + `<!--${val}-->` + this.newLine;
        } else if (key[0] === "?") {
          return this.indentate(level) + "<" + key + attrStr + "?" + this.tagEndChar;
        } else {
          let textValue = this.options.tagValueProcessor(key, val);
          textValue = this.replaceEntitiesValue(textValue);
          if (textValue === "") {
            return this.indentate(level) + "<" + key + attrStr + this.closeTag(key) + this.tagEndChar;
          } else {
            return this.indentate(level) + "<" + key + attrStr + ">" + textValue + "</" + key + this.tagEndChar;
          }
        }
      };
      Builder.prototype.replaceEntitiesValue = function(textValue) {
        if (textValue && textValue.length > 0 && this.options.processEntities) {
          for (let i2 = 0; i2 < this.options.entities.length; i2++) {
            const entity = this.options.entities[i2];
            textValue = textValue.replace(entity.regex, entity.val);
          }
        }
        return textValue;
      };
      function indentate(level) {
        return this.options.indentBy.repeat(level);
      }
      function isAttribute(name) {
        if (name.startsWith(this.options.attributeNamePrefix) && name !== this.options.textNodeName) {
          return name.substr(this.attrPrefixLen);
        } else {
          return false;
        }
      }
      module.exports = Builder;
    }
  });

  // node_modules/fast-xml-parser/src/fxp.js
  var require_fxp = __commonJS({
    "node_modules/fast-xml-parser/src/fxp.js"(exports, module) {
      "use strict";
      var validator = require_validator();
      var XMLParser5 = require_XMLParser();
      var XMLBuilder = require_json2xml();
      module.exports = {
        XMLParser: XMLParser5,
        XMLValidator: validator,
        XMLBuilder
      };
    }
  });

  // src/engine/index.ts
  var index_exports = {};
  __export(index_exports, {
    BANK_PROFILES: () => BANK_PROFILES,
    BUILT_IN_CATEGORIES: () => BUILT_IN_CATEGORIES,
    CATEGORY_LOOK: () => CATEGORY_LOOK,
    CUSTOM_CATEGORY_LOOK: () => CUSTOM_CATEGORY_LOOK,
    DEFAULT_CATEGORIES: () => DEFAULT_CATEGORIES,
    OWN_TRANSFERS: () => OWN_TRANSFERS,
    STARTER_RULES: () => STARTER_RULES,
    applyPlan: () => applyPlan,
    buildDashboard: () => buildDashboard,
    buildDashboardSource: () => buildDashboardSource,
    buildLedgerDashboard: () => buildLedgerDashboard,
    cardMerchant: () => cardMerchant,
    categoryLook: () => categoryLook,
    decodeBankFile: () => decodeBankFile,
    detectBankFile: () => detectBankFile,
    emptyLedgerSettings: () => emptyLedgerSettings,
    findLocalPlace: () => findLocalPlace,
    fixedCostEntries: () => fixedCostEntries,
    fixedCostList: () => fixedCostList,
    guessCsvLayout: () => guessCsvLayout,
    indexLocalPlaces: () => indexLocalPlaces,
    learn: () => learn,
    matchReceipt: () => matchReceipt,
    merchantKey: () => merchantKey,
    monthlyAverage: () => monthlyAverage,
    nextFixedDay: () => nextFixedDay,
    ownTransfers: () => ownTransfers,
    parseCamt: () => parseCamt2,
    parsePaypalCsv: () => parsePaypalCsv3,
    parseVrBankCsv: () => parseVrBankCsv2,
    paybackChoices: () => paybackChoices,
    planPaybacks: () => planPaybacks,
    quickSortGroups: () => quickSortGroups,
    readBankFile: () => readBankFile,
    readBankText: () => readBankText,
    readCamt: () => readCamt,
    readCsv: () => readCsv,
    readMt940: () => readMt940,
    readReceipt: () => readReceipt,
    readingsOfUnknownFile: () => readingsOfUnknownFile,
    selectionSummary: () => selectionSummary,
    setLocalPlaces: () => setLocalPlaces,
    shareableLayout: () => shareableLayout,
    shopIdentities: () => shopIdentities,
    sortPayments: () => sortPayments,
    starterCategory: () => starterCategory,
    version: () => version
  });

  // node_modules/csv-parse/dist/esm/sync.js
  var global$1 = typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {};
  var lookup = [];
  var revLookup = [];
  var Arr = typeof Uint8Array !== "undefined" ? Uint8Array : Array;
  var inited = false;
  function init() {
    inited = true;
    var code = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (var i2 = 0, len = code.length; i2 < len; ++i2) {
      lookup[i2] = code[i2];
      revLookup[code.charCodeAt(i2)] = i2;
    }
    revLookup["-".charCodeAt(0)] = 62;
    revLookup["_".charCodeAt(0)] = 63;
  }
  function toByteArray(b64) {
    if (!inited) {
      init();
    }
    var i2, j, l, tmp, placeHolders, arr4;
    var len = b64.length;
    if (len % 4 > 0) {
      throw new Error("Invalid string. Length must be a multiple of 4");
    }
    placeHolders = b64[len - 2] === "=" ? 2 : b64[len - 1] === "=" ? 1 : 0;
    arr4 = new Arr(len * 3 / 4 - placeHolders);
    l = placeHolders > 0 ? len - 4 : len;
    var L = 0;
    for (i2 = 0, j = 0; i2 < l; i2 += 4, j += 3) {
      tmp = revLookup[b64.charCodeAt(i2)] << 18 | revLookup[b64.charCodeAt(i2 + 1)] << 12 | revLookup[b64.charCodeAt(i2 + 2)] << 6 | revLookup[b64.charCodeAt(i2 + 3)];
      arr4[L++] = tmp >> 16 & 255;
      arr4[L++] = tmp >> 8 & 255;
      arr4[L++] = tmp & 255;
    }
    if (placeHolders === 2) {
      tmp = revLookup[b64.charCodeAt(i2)] << 2 | revLookup[b64.charCodeAt(i2 + 1)] >> 4;
      arr4[L++] = tmp & 255;
    } else if (placeHolders === 1) {
      tmp = revLookup[b64.charCodeAt(i2)] << 10 | revLookup[b64.charCodeAt(i2 + 1)] << 4 | revLookup[b64.charCodeAt(i2 + 2)] >> 2;
      arr4[L++] = tmp >> 8 & 255;
      arr4[L++] = tmp & 255;
    }
    return arr4;
  }
  function tripletToBase64(num) {
    return lookup[num >> 18 & 63] + lookup[num >> 12 & 63] + lookup[num >> 6 & 63] + lookup[num & 63];
  }
  function encodeChunk(uint8, start, end) {
    var tmp;
    var output = [];
    for (var i2 = start; i2 < end; i2 += 3) {
      tmp = (uint8[i2] << 16) + (uint8[i2 + 1] << 8) + uint8[i2 + 2];
      output.push(tripletToBase64(tmp));
    }
    return output.join("");
  }
  function fromByteArray(uint8) {
    if (!inited) {
      init();
    }
    var tmp;
    var len = uint8.length;
    var extraBytes = len % 3;
    var output = "";
    var parts = [];
    var maxChunkLength = 16383;
    for (var i2 = 0, len2 = len - extraBytes; i2 < len2; i2 += maxChunkLength) {
      parts.push(encodeChunk(uint8, i2, i2 + maxChunkLength > len2 ? len2 : i2 + maxChunkLength));
    }
    if (extraBytes === 1) {
      tmp = uint8[len - 1];
      output += lookup[tmp >> 2];
      output += lookup[tmp << 4 & 63];
      output += "==";
    } else if (extraBytes === 2) {
      tmp = (uint8[len - 2] << 8) + uint8[len - 1];
      output += lookup[tmp >> 10];
      output += lookup[tmp >> 4 & 63];
      output += lookup[tmp << 2 & 63];
      output += "=";
    }
    parts.push(output);
    return parts.join("");
  }
  function read(buffer, offset, isLE, mLen, nBytes) {
    var e, m;
    var eLen = nBytes * 8 - mLen - 1;
    var eMax = (1 << eLen) - 1;
    var eBias = eMax >> 1;
    var nBits = -7;
    var i2 = isLE ? nBytes - 1 : 0;
    var d = isLE ? -1 : 1;
    var s = buffer[offset + i2];
    i2 += d;
    e = s & (1 << -nBits) - 1;
    s >>= -nBits;
    nBits += eLen;
    for (; nBits > 0; e = e * 256 + buffer[offset + i2], i2 += d, nBits -= 8) {
    }
    m = e & (1 << -nBits) - 1;
    e >>= -nBits;
    nBits += mLen;
    for (; nBits > 0; m = m * 256 + buffer[offset + i2], i2 += d, nBits -= 8) {
    }
    if (e === 0) {
      e = 1 - eBias;
    } else if (e === eMax) {
      return m ? NaN : (s ? -1 : 1) * Infinity;
    } else {
      m = m + Math.pow(2, mLen);
      e = e - eBias;
    }
    return (s ? -1 : 1) * m * Math.pow(2, e - mLen);
  }
  function write(buffer, value, offset, isLE, mLen, nBytes) {
    var e, m, c;
    var eLen = nBytes * 8 - mLen - 1;
    var eMax = (1 << eLen) - 1;
    var eBias = eMax >> 1;
    var rt = mLen === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0;
    var i2 = isLE ? 0 : nBytes - 1;
    var d = isLE ? 1 : -1;
    var s = value < 0 || value === 0 && 1 / value < 0 ? 1 : 0;
    value = Math.abs(value);
    if (isNaN(value) || value === Infinity) {
      m = isNaN(value) ? 1 : 0;
      e = eMax;
    } else {
      e = Math.floor(Math.log(value) / Math.LN2);
      if (value * (c = Math.pow(2, -e)) < 1) {
        e--;
        c *= 2;
      }
      if (e + eBias >= 1) {
        value += rt / c;
      } else {
        value += rt * Math.pow(2, 1 - eBias);
      }
      if (value * c >= 2) {
        e++;
        c /= 2;
      }
      if (e + eBias >= eMax) {
        m = 0;
        e = eMax;
      } else if (e + eBias >= 1) {
        m = (value * c - 1) * Math.pow(2, mLen);
        e = e + eBias;
      } else {
        m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen);
        e = 0;
      }
    }
    for (; mLen >= 8; buffer[offset + i2] = m & 255, i2 += d, m /= 256, mLen -= 8) {
    }
    e = e << mLen | m;
    eLen += mLen;
    for (; eLen > 0; buffer[offset + i2] = e & 255, i2 += d, e /= 256, eLen -= 8) {
    }
    buffer[offset + i2 - d] |= s * 128;
  }
  var toString = {}.toString;
  var isArray = Array.isArray || function(arr4) {
    return toString.call(arr4) == "[object Array]";
  };
  var INSPECT_MAX_BYTES = 50;
  Buffer2.TYPED_ARRAY_SUPPORT = global$1.TYPED_ARRAY_SUPPORT !== void 0 ? global$1.TYPED_ARRAY_SUPPORT : true;
  kMaxLength();
  function kMaxLength() {
    return Buffer2.TYPED_ARRAY_SUPPORT ? 2147483647 : 1073741823;
  }
  function createBuffer(that, length) {
    if (kMaxLength() < length) {
      throw new RangeError("Invalid typed array length");
    }
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      that = new Uint8Array(length);
      that.__proto__ = Buffer2.prototype;
    } else {
      if (that === null) {
        that = new Buffer2(length);
      }
      that.length = length;
    }
    return that;
  }
  function Buffer2(arg, encodingOrOffset, length) {
    if (!Buffer2.TYPED_ARRAY_SUPPORT && !(this instanceof Buffer2)) {
      return new Buffer2(arg, encodingOrOffset, length);
    }
    if (typeof arg === "number") {
      if (typeof encodingOrOffset === "string") {
        throw new Error(
          "If encoding is specified then the first argument must be a string"
        );
      }
      return allocUnsafe(this, arg);
    }
    return from(this, arg, encodingOrOffset, length);
  }
  Buffer2.poolSize = 8192;
  Buffer2._augment = function(arr4) {
    arr4.__proto__ = Buffer2.prototype;
    return arr4;
  };
  function from(that, value, encodingOrOffset, length) {
    if (typeof value === "number") {
      throw new TypeError('"value" argument must not be a number');
    }
    if (typeof ArrayBuffer !== "undefined" && value instanceof ArrayBuffer) {
      return fromArrayBuffer(that, value, encodingOrOffset, length);
    }
    if (typeof value === "string") {
      return fromString(that, value, encodingOrOffset);
    }
    return fromObject(that, value);
  }
  Buffer2.from = function(value, encodingOrOffset, length) {
    return from(null, value, encodingOrOffset, length);
  };
  if (Buffer2.TYPED_ARRAY_SUPPORT) {
    Buffer2.prototype.__proto__ = Uint8Array.prototype;
    Buffer2.__proto__ = Uint8Array;
    if (typeof Symbol !== "undefined" && Symbol.species && Buffer2[Symbol.species] === Buffer2) ;
  }
  function assertSize(size) {
    if (typeof size !== "number") {
      throw new TypeError('"size" argument must be a number');
    } else if (size < 0) {
      throw new RangeError('"size" argument must not be negative');
    }
  }
  function alloc(that, size, fill2, encoding) {
    assertSize(size);
    if (size <= 0) {
      return createBuffer(that, size);
    }
    if (fill2 !== void 0) {
      return typeof encoding === "string" ? createBuffer(that, size).fill(fill2, encoding) : createBuffer(that, size).fill(fill2);
    }
    return createBuffer(that, size);
  }
  Buffer2.alloc = function(size, fill2, encoding) {
    return alloc(null, size, fill2, encoding);
  };
  function allocUnsafe(that, size) {
    assertSize(size);
    that = createBuffer(that, size < 0 ? 0 : checked(size) | 0);
    if (!Buffer2.TYPED_ARRAY_SUPPORT) {
      for (var i2 = 0; i2 < size; ++i2) {
        that[i2] = 0;
      }
    }
    return that;
  }
  Buffer2.allocUnsafe = function(size) {
    return allocUnsafe(null, size);
  };
  Buffer2.allocUnsafeSlow = function(size) {
    return allocUnsafe(null, size);
  };
  function fromString(that, string, encoding) {
    if (typeof encoding !== "string" || encoding === "") {
      encoding = "utf8";
    }
    if (!Buffer2.isEncoding(encoding)) {
      throw new TypeError('"encoding" must be a valid string encoding');
    }
    var length = byteLength(string, encoding) | 0;
    that = createBuffer(that, length);
    var actual = that.write(string, encoding);
    if (actual !== length) {
      that = that.slice(0, actual);
    }
    return that;
  }
  function fromArrayLike(that, array) {
    var length = array.length < 0 ? 0 : checked(array.length) | 0;
    that = createBuffer(that, length);
    for (var i2 = 0; i2 < length; i2 += 1) {
      that[i2] = array[i2] & 255;
    }
    return that;
  }
  function fromArrayBuffer(that, array, byteOffset, length) {
    array.byteLength;
    if (byteOffset < 0 || array.byteLength < byteOffset) {
      throw new RangeError("'offset' is out of bounds");
    }
    if (array.byteLength < byteOffset + (length || 0)) {
      throw new RangeError("'length' is out of bounds");
    }
    if (byteOffset === void 0 && length === void 0) {
      array = new Uint8Array(array);
    } else if (length === void 0) {
      array = new Uint8Array(array, byteOffset);
    } else {
      array = new Uint8Array(array, byteOffset, length);
    }
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      that = array;
      that.__proto__ = Buffer2.prototype;
    } else {
      that = fromArrayLike(that, array);
    }
    return that;
  }
  function fromObject(that, obj) {
    if (internalIsBuffer(obj)) {
      var len = checked(obj.length) | 0;
      that = createBuffer(that, len);
      if (that.length === 0) {
        return that;
      }
      obj.copy(that, 0, 0, len);
      return that;
    }
    if (obj) {
      if (typeof ArrayBuffer !== "undefined" && obj.buffer instanceof ArrayBuffer || "length" in obj) {
        if (typeof obj.length !== "number" || isnan(obj.length)) {
          return createBuffer(that, 0);
        }
        return fromArrayLike(that, obj);
      }
      if (obj.type === "Buffer" && isArray(obj.data)) {
        return fromArrayLike(that, obj.data);
      }
    }
    throw new TypeError("First argument must be a string, Buffer, ArrayBuffer, Array, or array-like object.");
  }
  function checked(length) {
    if (length >= kMaxLength()) {
      throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + kMaxLength().toString(16) + " bytes");
    }
    return length | 0;
  }
  Buffer2.isBuffer = isBuffer;
  function internalIsBuffer(b) {
    return !!(b != null && b._isBuffer);
  }
  Buffer2.compare = function compare(a, b) {
    if (!internalIsBuffer(a) || !internalIsBuffer(b)) {
      throw new TypeError("Arguments must be Buffers");
    }
    if (a === b) return 0;
    var x2 = a.length;
    var y = b.length;
    for (var i2 = 0, len = Math.min(x2, y); i2 < len; ++i2) {
      if (a[i2] !== b[i2]) {
        x2 = a[i2];
        y = b[i2];
        break;
      }
    }
    if (x2 < y) return -1;
    if (y < x2) return 1;
    return 0;
  };
  Buffer2.isEncoding = function isEncoding(encoding) {
    switch (String(encoding).toLowerCase()) {
      case "hex":
      case "utf8":
      case "utf-8":
      case "ascii":
      case "latin1":
      case "binary":
      case "base64":
      case "ucs2":
      case "ucs-2":
      case "utf16le":
      case "utf-16le":
        return true;
      default:
        return false;
    }
  };
  Buffer2.concat = function concat(list2, length) {
    if (!isArray(list2)) {
      throw new TypeError('"list" argument must be an Array of Buffers');
    }
    if (list2.length === 0) {
      return Buffer2.alloc(0);
    }
    var i2;
    if (length === void 0) {
      length = 0;
      for (i2 = 0; i2 < list2.length; ++i2) {
        length += list2[i2].length;
      }
    }
    var buffer = Buffer2.allocUnsafe(length);
    var pos = 0;
    for (i2 = 0; i2 < list2.length; ++i2) {
      var buf = list2[i2];
      if (!internalIsBuffer(buf)) {
        throw new TypeError('"list" argument must be an Array of Buffers');
      }
      buf.copy(buffer, pos);
      pos += buf.length;
    }
    return buffer;
  };
  function byteLength(string, encoding) {
    if (internalIsBuffer(string)) {
      return string.length;
    }
    if (typeof ArrayBuffer !== "undefined" && typeof ArrayBuffer.isView === "function" && (ArrayBuffer.isView(string) || string instanceof ArrayBuffer)) {
      return string.byteLength;
    }
    if (typeof string !== "string") {
      string = "" + string;
    }
    var len = string.length;
    if (len === 0) return 0;
    var loweredCase = false;
    for (; ; ) {
      switch (encoding) {
        case "ascii":
        case "latin1":
        case "binary":
          return len;
        case "utf8":
        case "utf-8":
        case void 0:
          return utf8ToBytes(string).length;
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return len * 2;
        case "hex":
          return len >>> 1;
        case "base64":
          return base64ToBytes(string).length;
        default:
          if (loweredCase) return utf8ToBytes(string).length;
          encoding = ("" + encoding).toLowerCase();
          loweredCase = true;
      }
    }
  }
  Buffer2.byteLength = byteLength;
  function slowToString(encoding, start, end) {
    var loweredCase = false;
    if (start === void 0 || start < 0) {
      start = 0;
    }
    if (start > this.length) {
      return "";
    }
    if (end === void 0 || end > this.length) {
      end = this.length;
    }
    if (end <= 0) {
      return "";
    }
    end >>>= 0;
    start >>>= 0;
    if (end <= start) {
      return "";
    }
    if (!encoding) encoding = "utf8";
    while (true) {
      switch (encoding) {
        case "hex":
          return hexSlice(this, start, end);
        case "utf8":
        case "utf-8":
          return utf8Slice(this, start, end);
        case "ascii":
          return asciiSlice(this, start, end);
        case "latin1":
        case "binary":
          return latin1Slice(this, start, end);
        case "base64":
          return base64Slice(this, start, end);
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return utf16leSlice(this, start, end);
        default:
          if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
          encoding = (encoding + "").toLowerCase();
          loweredCase = true;
      }
    }
  }
  Buffer2.prototype._isBuffer = true;
  function swap(b, n, m) {
    var i2 = b[n];
    b[n] = b[m];
    b[m] = i2;
  }
  Buffer2.prototype.swap16 = function swap16() {
    var len = this.length;
    if (len % 2 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 16-bits");
    }
    for (var i2 = 0; i2 < len; i2 += 2) {
      swap(this, i2, i2 + 1);
    }
    return this;
  };
  Buffer2.prototype.swap32 = function swap32() {
    var len = this.length;
    if (len % 4 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 32-bits");
    }
    for (var i2 = 0; i2 < len; i2 += 4) {
      swap(this, i2, i2 + 3);
      swap(this, i2 + 1, i2 + 2);
    }
    return this;
  };
  Buffer2.prototype.swap64 = function swap64() {
    var len = this.length;
    if (len % 8 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 64-bits");
    }
    for (var i2 = 0; i2 < len; i2 += 8) {
      swap(this, i2, i2 + 7);
      swap(this, i2 + 1, i2 + 6);
      swap(this, i2 + 2, i2 + 5);
      swap(this, i2 + 3, i2 + 4);
    }
    return this;
  };
  Buffer2.prototype.toString = function toString2() {
    var length = this.length | 0;
    if (length === 0) return "";
    if (arguments.length === 0) return utf8Slice(this, 0, length);
    return slowToString.apply(this, arguments);
  };
  Buffer2.prototype.equals = function equals(b) {
    if (!internalIsBuffer(b)) throw new TypeError("Argument must be a Buffer");
    if (this === b) return true;
    return Buffer2.compare(this, b) === 0;
  };
  Buffer2.prototype.inspect = function inspect() {
    var str = "";
    var max2 = INSPECT_MAX_BYTES;
    if (this.length > 0) {
      str = this.toString("hex", 0, max2).match(/.{2}/g).join(" ");
      if (this.length > max2) str += " ... ";
    }
    return "<Buffer " + str + ">";
  };
  Buffer2.prototype.compare = function compare2(target, start, end, thisStart, thisEnd) {
    if (!internalIsBuffer(target)) {
      throw new TypeError("Argument must be a Buffer");
    }
    if (start === void 0) {
      start = 0;
    }
    if (end === void 0) {
      end = target ? target.length : 0;
    }
    if (thisStart === void 0) {
      thisStart = 0;
    }
    if (thisEnd === void 0) {
      thisEnd = this.length;
    }
    if (start < 0 || end > target.length || thisStart < 0 || thisEnd > this.length) {
      throw new RangeError("out of range index");
    }
    if (thisStart >= thisEnd && start >= end) {
      return 0;
    }
    if (thisStart >= thisEnd) {
      return -1;
    }
    if (start >= end) {
      return 1;
    }
    start >>>= 0;
    end >>>= 0;
    thisStart >>>= 0;
    thisEnd >>>= 0;
    if (this === target) return 0;
    var x2 = thisEnd - thisStart;
    var y = end - start;
    var len = Math.min(x2, y);
    var thisCopy = this.slice(thisStart, thisEnd);
    var targetCopy = target.slice(start, end);
    for (var i2 = 0; i2 < len; ++i2) {
      if (thisCopy[i2] !== targetCopy[i2]) {
        x2 = thisCopy[i2];
        y = targetCopy[i2];
        break;
      }
    }
    if (x2 < y) return -1;
    if (y < x2) return 1;
    return 0;
  };
  function bidirectionalIndexOf(buffer, val, byteOffset, encoding, dir) {
    if (buffer.length === 0) return -1;
    if (typeof byteOffset === "string") {
      encoding = byteOffset;
      byteOffset = 0;
    } else if (byteOffset > 2147483647) {
      byteOffset = 2147483647;
    } else if (byteOffset < -2147483648) {
      byteOffset = -2147483648;
    }
    byteOffset = +byteOffset;
    if (isNaN(byteOffset)) {
      byteOffset = dir ? 0 : buffer.length - 1;
    }
    if (byteOffset < 0) byteOffset = buffer.length + byteOffset;
    if (byteOffset >= buffer.length) {
      if (dir) return -1;
      else byteOffset = buffer.length - 1;
    } else if (byteOffset < 0) {
      if (dir) byteOffset = 0;
      else return -1;
    }
    if (typeof val === "string") {
      val = Buffer2.from(val, encoding);
    }
    if (internalIsBuffer(val)) {
      if (val.length === 0) {
        return -1;
      }
      return arrayIndexOf(buffer, val, byteOffset, encoding, dir);
    } else if (typeof val === "number") {
      val = val & 255;
      if (Buffer2.TYPED_ARRAY_SUPPORT && typeof Uint8Array.prototype.indexOf === "function") {
        if (dir) {
          return Uint8Array.prototype.indexOf.call(buffer, val, byteOffset);
        } else {
          return Uint8Array.prototype.lastIndexOf.call(buffer, val, byteOffset);
        }
      }
      return arrayIndexOf(buffer, [val], byteOffset, encoding, dir);
    }
    throw new TypeError("val must be string, number or Buffer");
  }
  function arrayIndexOf(arr4, val, byteOffset, encoding, dir) {
    var indexSize = 1;
    var arrLength = arr4.length;
    var valLength = val.length;
    if (encoding !== void 0) {
      encoding = String(encoding).toLowerCase();
      if (encoding === "ucs2" || encoding === "ucs-2" || encoding === "utf16le" || encoding === "utf-16le") {
        if (arr4.length < 2 || val.length < 2) {
          return -1;
        }
        indexSize = 2;
        arrLength /= 2;
        valLength /= 2;
        byteOffset /= 2;
      }
    }
    function read2(buf, i3) {
      if (indexSize === 1) {
        return buf[i3];
      } else {
        return buf.readUInt16BE(i3 * indexSize);
      }
    }
    var i2;
    if (dir) {
      var foundIndex = -1;
      for (i2 = byteOffset; i2 < arrLength; i2++) {
        if (read2(arr4, i2) === read2(val, foundIndex === -1 ? 0 : i2 - foundIndex)) {
          if (foundIndex === -1) foundIndex = i2;
          if (i2 - foundIndex + 1 === valLength) return foundIndex * indexSize;
        } else {
          if (foundIndex !== -1) i2 -= i2 - foundIndex;
          foundIndex = -1;
        }
      }
    } else {
      if (byteOffset + valLength > arrLength) byteOffset = arrLength - valLength;
      for (i2 = byteOffset; i2 >= 0; i2--) {
        var found = true;
        for (var j = 0; j < valLength; j++) {
          if (read2(arr4, i2 + j) !== read2(val, j)) {
            found = false;
            break;
          }
        }
        if (found) return i2;
      }
    }
    return -1;
  }
  Buffer2.prototype.includes = function includes(val, byteOffset, encoding) {
    return this.indexOf(val, byteOffset, encoding) !== -1;
  };
  Buffer2.prototype.indexOf = function indexOf(val, byteOffset, encoding) {
    return bidirectionalIndexOf(this, val, byteOffset, encoding, true);
  };
  Buffer2.prototype.lastIndexOf = function lastIndexOf(val, byteOffset, encoding) {
    return bidirectionalIndexOf(this, val, byteOffset, encoding, false);
  };
  function hexWrite(buf, string, offset, length) {
    offset = Number(offset) || 0;
    var remaining2 = buf.length - offset;
    if (!length) {
      length = remaining2;
    } else {
      length = Number(length);
      if (length > remaining2) {
        length = remaining2;
      }
    }
    var strLen = string.length;
    if (strLen % 2 !== 0) throw new TypeError("Invalid hex string");
    if (length > strLen / 2) {
      length = strLen / 2;
    }
    for (var i2 = 0; i2 < length; ++i2) {
      var parsed = parseInt(string.substr(i2 * 2, 2), 16);
      if (isNaN(parsed)) return i2;
      buf[offset + i2] = parsed;
    }
    return i2;
  }
  function utf8Write(buf, string, offset, length) {
    return blitBuffer(utf8ToBytes(string, buf.length - offset), buf, offset, length);
  }
  function asciiWrite(buf, string, offset, length) {
    return blitBuffer(asciiToBytes(string), buf, offset, length);
  }
  function latin1Write(buf, string, offset, length) {
    return asciiWrite(buf, string, offset, length);
  }
  function base64Write(buf, string, offset, length) {
    return blitBuffer(base64ToBytes(string), buf, offset, length);
  }
  function ucs2Write(buf, string, offset, length) {
    return blitBuffer(utf16leToBytes(string, buf.length - offset), buf, offset, length);
  }
  Buffer2.prototype.write = function write2(string, offset, length, encoding) {
    if (offset === void 0) {
      encoding = "utf8";
      length = this.length;
      offset = 0;
    } else if (length === void 0 && typeof offset === "string") {
      encoding = offset;
      length = this.length;
      offset = 0;
    } else if (isFinite(offset)) {
      offset = offset | 0;
      if (isFinite(length)) {
        length = length | 0;
        if (encoding === void 0) encoding = "utf8";
      } else {
        encoding = length;
        length = void 0;
      }
    } else {
      throw new Error(
        "Buffer.write(string, encoding, offset[, length]) is no longer supported"
      );
    }
    var remaining2 = this.length - offset;
    if (length === void 0 || length > remaining2) length = remaining2;
    if (string.length > 0 && (length < 0 || offset < 0) || offset > this.length) {
      throw new RangeError("Attempt to write outside buffer bounds");
    }
    if (!encoding) encoding = "utf8";
    var loweredCase = false;
    for (; ; ) {
      switch (encoding) {
        case "hex":
          return hexWrite(this, string, offset, length);
        case "utf8":
        case "utf-8":
          return utf8Write(this, string, offset, length);
        case "ascii":
          return asciiWrite(this, string, offset, length);
        case "latin1":
        case "binary":
          return latin1Write(this, string, offset, length);
        case "base64":
          return base64Write(this, string, offset, length);
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return ucs2Write(this, string, offset, length);
        default:
          if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
          encoding = ("" + encoding).toLowerCase();
          loweredCase = true;
      }
    }
  };
  Buffer2.prototype.toJSON = function toJSON() {
    return {
      type: "Buffer",
      data: Array.prototype.slice.call(this._arr || this, 0)
    };
  };
  function base64Slice(buf, start, end) {
    if (start === 0 && end === buf.length) {
      return fromByteArray(buf);
    } else {
      return fromByteArray(buf.slice(start, end));
    }
  }
  function utf8Slice(buf, start, end) {
    end = Math.min(buf.length, end);
    var res = [];
    var i2 = start;
    while (i2 < end) {
      var firstByte = buf[i2];
      var codePoint = null;
      var bytesPerSequence = firstByte > 239 ? 4 : firstByte > 223 ? 3 : firstByte > 191 ? 2 : 1;
      if (i2 + bytesPerSequence <= end) {
        var secondByte, thirdByte, fourthByte, tempCodePoint;
        switch (bytesPerSequence) {
          case 1:
            if (firstByte < 128) {
              codePoint = firstByte;
            }
            break;
          case 2:
            secondByte = buf[i2 + 1];
            if ((secondByte & 192) === 128) {
              tempCodePoint = (firstByte & 31) << 6 | secondByte & 63;
              if (tempCodePoint > 127) {
                codePoint = tempCodePoint;
              }
            }
            break;
          case 3:
            secondByte = buf[i2 + 1];
            thirdByte = buf[i2 + 2];
            if ((secondByte & 192) === 128 && (thirdByte & 192) === 128) {
              tempCodePoint = (firstByte & 15) << 12 | (secondByte & 63) << 6 | thirdByte & 63;
              if (tempCodePoint > 2047 && (tempCodePoint < 55296 || tempCodePoint > 57343)) {
                codePoint = tempCodePoint;
              }
            }
            break;
          case 4:
            secondByte = buf[i2 + 1];
            thirdByte = buf[i2 + 2];
            fourthByte = buf[i2 + 3];
            if ((secondByte & 192) === 128 && (thirdByte & 192) === 128 && (fourthByte & 192) === 128) {
              tempCodePoint = (firstByte & 15) << 18 | (secondByte & 63) << 12 | (thirdByte & 63) << 6 | fourthByte & 63;
              if (tempCodePoint > 65535 && tempCodePoint < 1114112) {
                codePoint = tempCodePoint;
              }
            }
        }
      }
      if (codePoint === null) {
        codePoint = 65533;
        bytesPerSequence = 1;
      } else if (codePoint > 65535) {
        codePoint -= 65536;
        res.push(codePoint >>> 10 & 1023 | 55296);
        codePoint = 56320 | codePoint & 1023;
      }
      res.push(codePoint);
      i2 += bytesPerSequence;
    }
    return decodeCodePointsArray(res);
  }
  var MAX_ARGUMENTS_LENGTH = 4096;
  function decodeCodePointsArray(codePoints) {
    var len = codePoints.length;
    if (len <= MAX_ARGUMENTS_LENGTH) {
      return String.fromCharCode.apply(String, codePoints);
    }
    var res = "";
    var i2 = 0;
    while (i2 < len) {
      res += String.fromCharCode.apply(
        String,
        codePoints.slice(i2, i2 += MAX_ARGUMENTS_LENGTH)
      );
    }
    return res;
  }
  function asciiSlice(buf, start, end) {
    var ret = "";
    end = Math.min(buf.length, end);
    for (var i2 = start; i2 < end; ++i2) {
      ret += String.fromCharCode(buf[i2] & 127);
    }
    return ret;
  }
  function latin1Slice(buf, start, end) {
    var ret = "";
    end = Math.min(buf.length, end);
    for (var i2 = start; i2 < end; ++i2) {
      ret += String.fromCharCode(buf[i2]);
    }
    return ret;
  }
  function hexSlice(buf, start, end) {
    var len = buf.length;
    if (!start || start < 0) start = 0;
    if (!end || end < 0 || end > len) end = len;
    var out = "";
    for (var i2 = start; i2 < end; ++i2) {
      out += toHex(buf[i2]);
    }
    return out;
  }
  function utf16leSlice(buf, start, end) {
    var bytes = buf.slice(start, end);
    var res = "";
    for (var i2 = 0; i2 < bytes.length; i2 += 2) {
      res += String.fromCharCode(bytes[i2] + bytes[i2 + 1] * 256);
    }
    return res;
  }
  Buffer2.prototype.slice = function slice(start, end) {
    var len = this.length;
    start = ~~start;
    end = end === void 0 ? len : ~~end;
    if (start < 0) {
      start += len;
      if (start < 0) start = 0;
    } else if (start > len) {
      start = len;
    }
    if (end < 0) {
      end += len;
      if (end < 0) end = 0;
    } else if (end > len) {
      end = len;
    }
    if (end < start) end = start;
    var newBuf;
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      newBuf = this.subarray(start, end);
      newBuf.__proto__ = Buffer2.prototype;
    } else {
      var sliceLen = end - start;
      newBuf = new Buffer2(sliceLen, void 0);
      for (var i2 = 0; i2 < sliceLen; ++i2) {
        newBuf[i2] = this[i2 + start];
      }
    }
    return newBuf;
  };
  function checkOffset(offset, ext, length) {
    if (offset % 1 !== 0 || offset < 0) throw new RangeError("offset is not uint");
    if (offset + ext > length) throw new RangeError("Trying to access beyond buffer length");
  }
  Buffer2.prototype.readUIntLE = function readUIntLE(offset, byteLength2, noAssert) {
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) checkOffset(offset, byteLength2, this.length);
    var val = this[offset];
    var mul = 1;
    var i2 = 0;
    while (++i2 < byteLength2 && (mul *= 256)) {
      val += this[offset + i2] * mul;
    }
    return val;
  };
  Buffer2.prototype.readUIntBE = function readUIntBE(offset, byteLength2, noAssert) {
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) {
      checkOffset(offset, byteLength2, this.length);
    }
    var val = this[offset + --byteLength2];
    var mul = 1;
    while (byteLength2 > 0 && (mul *= 256)) {
      val += this[offset + --byteLength2] * mul;
    }
    return val;
  };
  Buffer2.prototype.readUInt8 = function readUInt8(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 1, this.length);
    return this[offset];
  };
  Buffer2.prototype.readUInt16LE = function readUInt16LE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 2, this.length);
    return this[offset] | this[offset + 1] << 8;
  };
  Buffer2.prototype.readUInt16BE = function readUInt16BE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 2, this.length);
    return this[offset] << 8 | this[offset + 1];
  };
  Buffer2.prototype.readUInt32LE = function readUInt32LE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return (this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16) + this[offset + 3] * 16777216;
  };
  Buffer2.prototype.readUInt32BE = function readUInt32BE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return this[offset] * 16777216 + (this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3]);
  };
  Buffer2.prototype.readIntLE = function readIntLE(offset, byteLength2, noAssert) {
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) checkOffset(offset, byteLength2, this.length);
    var val = this[offset];
    var mul = 1;
    var i2 = 0;
    while (++i2 < byteLength2 && (mul *= 256)) {
      val += this[offset + i2] * mul;
    }
    mul *= 128;
    if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
    return val;
  };
  Buffer2.prototype.readIntBE = function readIntBE(offset, byteLength2, noAssert) {
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) checkOffset(offset, byteLength2, this.length);
    var i2 = byteLength2;
    var mul = 1;
    var val = this[offset + --i2];
    while (i2 > 0 && (mul *= 256)) {
      val += this[offset + --i2] * mul;
    }
    mul *= 128;
    if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
    return val;
  };
  Buffer2.prototype.readInt8 = function readInt8(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 1, this.length);
    if (!(this[offset] & 128)) return this[offset];
    return (255 - this[offset] + 1) * -1;
  };
  Buffer2.prototype.readInt16LE = function readInt16LE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 2, this.length);
    var val = this[offset] | this[offset + 1] << 8;
    return val & 32768 ? val | 4294901760 : val;
  };
  Buffer2.prototype.readInt16BE = function readInt16BE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 2, this.length);
    var val = this[offset + 1] | this[offset] << 8;
    return val & 32768 ? val | 4294901760 : val;
  };
  Buffer2.prototype.readInt32LE = function readInt32LE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16 | this[offset + 3] << 24;
  };
  Buffer2.prototype.readInt32BE = function readInt32BE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return this[offset] << 24 | this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3];
  };
  Buffer2.prototype.readFloatLE = function readFloatLE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return read(this, offset, true, 23, 4);
  };
  Buffer2.prototype.readFloatBE = function readFloatBE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 4, this.length);
    return read(this, offset, false, 23, 4);
  };
  Buffer2.prototype.readDoubleLE = function readDoubleLE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 8, this.length);
    return read(this, offset, true, 52, 8);
  };
  Buffer2.prototype.readDoubleBE = function readDoubleBE(offset, noAssert) {
    if (!noAssert) checkOffset(offset, 8, this.length);
    return read(this, offset, false, 52, 8);
  };
  function checkInt(buf, value, offset, ext, max2, min) {
    if (!internalIsBuffer(buf)) throw new TypeError('"buffer" argument must be a Buffer instance');
    if (value > max2 || value < min) throw new RangeError('"value" argument is out of bounds');
    if (offset + ext > buf.length) throw new RangeError("Index out of range");
  }
  Buffer2.prototype.writeUIntLE = function writeUIntLE(value, offset, byteLength2, noAssert) {
    value = +value;
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) {
      var maxBytes = Math.pow(2, 8 * byteLength2) - 1;
      checkInt(this, value, offset, byteLength2, maxBytes, 0);
    }
    var mul = 1;
    var i2 = 0;
    this[offset] = value & 255;
    while (++i2 < byteLength2 && (mul *= 256)) {
      this[offset + i2] = value / mul & 255;
    }
    return offset + byteLength2;
  };
  Buffer2.prototype.writeUIntBE = function writeUIntBE(value, offset, byteLength2, noAssert) {
    value = +value;
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) {
      var maxBytes = Math.pow(2, 8 * byteLength2) - 1;
      checkInt(this, value, offset, byteLength2, maxBytes, 0);
    }
    var i2 = byteLength2 - 1;
    var mul = 1;
    this[offset + i2] = value & 255;
    while (--i2 >= 0 && (mul *= 256)) {
      this[offset + i2] = value / mul & 255;
    }
    return offset + byteLength2;
  };
  Buffer2.prototype.writeUInt8 = function writeUInt8(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 1, 255, 0);
    if (!Buffer2.TYPED_ARRAY_SUPPORT) value = Math.floor(value);
    this[offset] = value & 255;
    return offset + 1;
  };
  function objectWriteUInt16(buf, value, offset, littleEndian) {
    if (value < 0) value = 65535 + value + 1;
    for (var i2 = 0, j = Math.min(buf.length - offset, 2); i2 < j; ++i2) {
      buf[offset + i2] = (value & 255 << 8 * (littleEndian ? i2 : 1 - i2)) >>> (littleEndian ? i2 : 1 - i2) * 8;
    }
  }
  Buffer2.prototype.writeUInt16LE = function writeUInt16LE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
    } else {
      objectWriteUInt16(this, value, offset, true);
    }
    return offset + 2;
  };
  Buffer2.prototype.writeUInt16BE = function writeUInt16BE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value >>> 8;
      this[offset + 1] = value & 255;
    } else {
      objectWriteUInt16(this, value, offset, false);
    }
    return offset + 2;
  };
  function objectWriteUInt32(buf, value, offset, littleEndian) {
    if (value < 0) value = 4294967295 + value + 1;
    for (var i2 = 0, j = Math.min(buf.length - offset, 4); i2 < j; ++i2) {
      buf[offset + i2] = value >>> (littleEndian ? i2 : 3 - i2) * 8 & 255;
    }
  }
  Buffer2.prototype.writeUInt32LE = function writeUInt32LE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset + 3] = value >>> 24;
      this[offset + 2] = value >>> 16;
      this[offset + 1] = value >>> 8;
      this[offset] = value & 255;
    } else {
      objectWriteUInt32(this, value, offset, true);
    }
    return offset + 4;
  };
  Buffer2.prototype.writeUInt32BE = function writeUInt32BE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value >>> 24;
      this[offset + 1] = value >>> 16;
      this[offset + 2] = value >>> 8;
      this[offset + 3] = value & 255;
    } else {
      objectWriteUInt32(this, value, offset, false);
    }
    return offset + 4;
  };
  Buffer2.prototype.writeIntLE = function writeIntLE(value, offset, byteLength2, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) {
      var limit2 = Math.pow(2, 8 * byteLength2 - 1);
      checkInt(this, value, offset, byteLength2, limit2 - 1, -limit2);
    }
    var i2 = 0;
    var mul = 1;
    var sub = 0;
    this[offset] = value & 255;
    while (++i2 < byteLength2 && (mul *= 256)) {
      if (value < 0 && sub === 0 && this[offset + i2 - 1] !== 0) {
        sub = 1;
      }
      this[offset + i2] = (value / mul >> 0) - sub & 255;
    }
    return offset + byteLength2;
  };
  Buffer2.prototype.writeIntBE = function writeIntBE(value, offset, byteLength2, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) {
      var limit2 = Math.pow(2, 8 * byteLength2 - 1);
      checkInt(this, value, offset, byteLength2, limit2 - 1, -limit2);
    }
    var i2 = byteLength2 - 1;
    var mul = 1;
    var sub = 0;
    this[offset + i2] = value & 255;
    while (--i2 >= 0 && (mul *= 256)) {
      if (value < 0 && sub === 0 && this[offset + i2 + 1] !== 0) {
        sub = 1;
      }
      this[offset + i2] = (value / mul >> 0) - sub & 255;
    }
    return offset + byteLength2;
  };
  Buffer2.prototype.writeInt8 = function writeInt8(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 1, 127, -128);
    if (!Buffer2.TYPED_ARRAY_SUPPORT) value = Math.floor(value);
    if (value < 0) value = 255 + value + 1;
    this[offset] = value & 255;
    return offset + 1;
  };
  Buffer2.prototype.writeInt16LE = function writeInt16LE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
    } else {
      objectWriteUInt16(this, value, offset, true);
    }
    return offset + 2;
  };
  Buffer2.prototype.writeInt16BE = function writeInt16BE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value >>> 8;
      this[offset + 1] = value & 255;
    } else {
      objectWriteUInt16(this, value, offset, false);
    }
    return offset + 2;
  };
  Buffer2.prototype.writeInt32LE = function writeInt32LE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
      this[offset + 2] = value >>> 16;
      this[offset + 3] = value >>> 24;
    } else {
      objectWriteUInt32(this, value, offset, true);
    }
    return offset + 4;
  };
  Buffer2.prototype.writeInt32BE = function writeInt32BE(value, offset, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
    if (value < 0) value = 4294967295 + value + 1;
    if (Buffer2.TYPED_ARRAY_SUPPORT) {
      this[offset] = value >>> 24;
      this[offset + 1] = value >>> 16;
      this[offset + 2] = value >>> 8;
      this[offset + 3] = value & 255;
    } else {
      objectWriteUInt32(this, value, offset, false);
    }
    return offset + 4;
  };
  function checkIEEE754(buf, value, offset, ext, max2, min) {
    if (offset + ext > buf.length) throw new RangeError("Index out of range");
    if (offset < 0) throw new RangeError("Index out of range");
  }
  function writeFloat(buf, value, offset, littleEndian, noAssert) {
    if (!noAssert) {
      checkIEEE754(buf, value, offset, 4);
    }
    write(buf, value, offset, littleEndian, 23, 4);
    return offset + 4;
  }
  Buffer2.prototype.writeFloatLE = function writeFloatLE(value, offset, noAssert) {
    return writeFloat(this, value, offset, true, noAssert);
  };
  Buffer2.prototype.writeFloatBE = function writeFloatBE(value, offset, noAssert) {
    return writeFloat(this, value, offset, false, noAssert);
  };
  function writeDouble(buf, value, offset, littleEndian, noAssert) {
    if (!noAssert) {
      checkIEEE754(buf, value, offset, 8);
    }
    write(buf, value, offset, littleEndian, 52, 8);
    return offset + 8;
  }
  Buffer2.prototype.writeDoubleLE = function writeDoubleLE(value, offset, noAssert) {
    return writeDouble(this, value, offset, true, noAssert);
  };
  Buffer2.prototype.writeDoubleBE = function writeDoubleBE(value, offset, noAssert) {
    return writeDouble(this, value, offset, false, noAssert);
  };
  Buffer2.prototype.copy = function copy(target, targetStart, start, end) {
    if (!start) start = 0;
    if (!end && end !== 0) end = this.length;
    if (targetStart >= target.length) targetStart = target.length;
    if (!targetStart) targetStart = 0;
    if (end > 0 && end < start) end = start;
    if (end === start) return 0;
    if (target.length === 0 || this.length === 0) return 0;
    if (targetStart < 0) {
      throw new RangeError("targetStart out of bounds");
    }
    if (start < 0 || start >= this.length) throw new RangeError("sourceStart out of bounds");
    if (end < 0) throw new RangeError("sourceEnd out of bounds");
    if (end > this.length) end = this.length;
    if (target.length - targetStart < end - start) {
      end = target.length - targetStart + start;
    }
    var len = end - start;
    var i2;
    if (this === target && start < targetStart && targetStart < end) {
      for (i2 = len - 1; i2 >= 0; --i2) {
        target[i2 + targetStart] = this[i2 + start];
      }
    } else if (len < 1e3 || !Buffer2.TYPED_ARRAY_SUPPORT) {
      for (i2 = 0; i2 < len; ++i2) {
        target[i2 + targetStart] = this[i2 + start];
      }
    } else {
      Uint8Array.prototype.set.call(
        target,
        this.subarray(start, start + len),
        targetStart
      );
    }
    return len;
  };
  Buffer2.prototype.fill = function fill(val, start, end, encoding) {
    if (typeof val === "string") {
      if (typeof start === "string") {
        encoding = start;
        start = 0;
        end = this.length;
      } else if (typeof end === "string") {
        encoding = end;
        end = this.length;
      }
      if (val.length === 1) {
        var code = val.charCodeAt(0);
        if (code < 256) {
          val = code;
        }
      }
      if (encoding !== void 0 && typeof encoding !== "string") {
        throw new TypeError("encoding must be a string");
      }
      if (typeof encoding === "string" && !Buffer2.isEncoding(encoding)) {
        throw new TypeError("Unknown encoding: " + encoding);
      }
    } else if (typeof val === "number") {
      val = val & 255;
    }
    if (start < 0 || this.length < start || this.length < end) {
      throw new RangeError("Out of range index");
    }
    if (end <= start) {
      return this;
    }
    start = start >>> 0;
    end = end === void 0 ? this.length : end >>> 0;
    if (!val) val = 0;
    var i2;
    if (typeof val === "number") {
      for (i2 = start; i2 < end; ++i2) {
        this[i2] = val;
      }
    } else {
      var bytes = internalIsBuffer(val) ? val : utf8ToBytes(new Buffer2(val, encoding).toString());
      var len = bytes.length;
      for (i2 = 0; i2 < end - start; ++i2) {
        this[i2 + start] = bytes[i2 % len];
      }
    }
    return this;
  };
  var INVALID_BASE64_RE = /[^+\/0-9A-Za-z-_]/g;
  function base64clean(str) {
    str = stringtrim(str).replace(INVALID_BASE64_RE, "");
    if (str.length < 2) return "";
    while (str.length % 4 !== 0) {
      str = str + "=";
    }
    return str;
  }
  function stringtrim(str) {
    if (str.trim) return str.trim();
    return str.replace(/^\s+|\s+$/g, "");
  }
  function toHex(n) {
    if (n < 16) return "0" + n.toString(16);
    return n.toString(16);
  }
  function utf8ToBytes(string, units) {
    units = units || Infinity;
    var codePoint;
    var length = string.length;
    var leadSurrogate = null;
    var bytes = [];
    for (var i2 = 0; i2 < length; ++i2) {
      codePoint = string.charCodeAt(i2);
      if (codePoint > 55295 && codePoint < 57344) {
        if (!leadSurrogate) {
          if (codePoint > 56319) {
            if ((units -= 3) > -1) bytes.push(239, 191, 189);
            continue;
          } else if (i2 + 1 === length) {
            if ((units -= 3) > -1) bytes.push(239, 191, 189);
            continue;
          }
          leadSurrogate = codePoint;
          continue;
        }
        if (codePoint < 56320) {
          if ((units -= 3) > -1) bytes.push(239, 191, 189);
          leadSurrogate = codePoint;
          continue;
        }
        codePoint = (leadSurrogate - 55296 << 10 | codePoint - 56320) + 65536;
      } else if (leadSurrogate) {
        if ((units -= 3) > -1) bytes.push(239, 191, 189);
      }
      leadSurrogate = null;
      if (codePoint < 128) {
        if ((units -= 1) < 0) break;
        bytes.push(codePoint);
      } else if (codePoint < 2048) {
        if ((units -= 2) < 0) break;
        bytes.push(
          codePoint >> 6 | 192,
          codePoint & 63 | 128
        );
      } else if (codePoint < 65536) {
        if ((units -= 3) < 0) break;
        bytes.push(
          codePoint >> 12 | 224,
          codePoint >> 6 & 63 | 128,
          codePoint & 63 | 128
        );
      } else if (codePoint < 1114112) {
        if ((units -= 4) < 0) break;
        bytes.push(
          codePoint >> 18 | 240,
          codePoint >> 12 & 63 | 128,
          codePoint >> 6 & 63 | 128,
          codePoint & 63 | 128
        );
      } else {
        throw new Error("Invalid code point");
      }
    }
    return bytes;
  }
  function asciiToBytes(str) {
    var byteArray = [];
    for (var i2 = 0; i2 < str.length; ++i2) {
      byteArray.push(str.charCodeAt(i2) & 255);
    }
    return byteArray;
  }
  function utf16leToBytes(str, units) {
    var c, hi, lo;
    var byteArray = [];
    for (var i2 = 0; i2 < str.length; ++i2) {
      if ((units -= 2) < 0) break;
      c = str.charCodeAt(i2);
      hi = c >> 8;
      lo = c % 256;
      byteArray.push(lo);
      byteArray.push(hi);
    }
    return byteArray;
  }
  function base64ToBytes(str) {
    return toByteArray(base64clean(str));
  }
  function blitBuffer(src, dst, offset, length) {
    for (var i2 = 0; i2 < length; ++i2) {
      if (i2 + offset >= dst.length || i2 >= src.length) break;
      dst[i2 + offset] = src[i2];
    }
    return i2;
  }
  function isnan(val) {
    return val !== val;
  }
  function isBuffer(obj) {
    return obj != null && (!!obj._isBuffer || isFastBuffer(obj) || isSlowBuffer(obj));
  }
  function isFastBuffer(obj) {
    return !!obj.constructor && typeof obj.constructor.isBuffer === "function" && obj.constructor.isBuffer(obj);
  }
  function isSlowBuffer(obj) {
    return typeof obj.readFloatLE === "function" && typeof obj.slice === "function" && isFastBuffer(obj.slice(0, 0));
  }
  var CsvError = class _CsvError extends Error {
    constructor(code, message, options, ...contexts) {
      if (Array.isArray(message)) message = message.join(" ").trim();
      super(message);
      if (Error.captureStackTrace !== void 0) {
        Error.captureStackTrace(this, _CsvError);
      }
      this.code = code;
      for (const context of contexts) {
        for (const key in context) {
          const value = context[key];
          this[key] = isBuffer(value) ? value.toString(options.encoding) : value == null ? value : JSON.parse(JSON.stringify(value));
        }
      }
    }
  };
  var is_object = function(obj) {
    return typeof obj === "object" && obj !== null && !Array.isArray(obj);
  };
  var normalize_columns_array = function(columns) {
    const normalizedColumns = [];
    for (let i2 = 0, l = columns.length; i2 < l; i2++) {
      const column = columns[i2];
      if (column === void 0 || column === null || column === false) {
        normalizedColumns[i2] = { disabled: true };
      } else if (typeof column === "string") {
        normalizedColumns[i2] = { name: column };
      } else if (is_object(column)) {
        if (typeof column.name !== "string") {
          throw new CsvError("CSV_OPTION_COLUMNS_MISSING_NAME", [
            "Option columns missing name:",
            `property "name" is required at position ${i2}`,
            "when column is an object literal"
          ]);
        }
        normalizedColumns[i2] = column;
      } else {
        throw new CsvError("CSV_INVALID_COLUMN_DEFINITION", [
          "Invalid column definition:",
          "expect a string or a literal object,",
          `got ${JSON.stringify(column)} at position ${i2}`
        ]);
      }
    }
    return normalizedColumns;
  };
  var ResizeableBuffer = class {
    constructor(size = 100) {
      this.size = size;
      this.length = 0;
      this.buf = Buffer2.allocUnsafe(size);
    }
    prepend(val) {
      if (isBuffer(val)) {
        const length = this.length + val.length;
        if (length >= this.size) {
          this.resize();
          if (length >= this.size) {
            throw Error("INVALID_BUFFER_STATE");
          }
        }
        const buf = this.buf;
        this.buf = Buffer2.allocUnsafe(this.size);
        val.copy(this.buf, 0);
        buf.copy(this.buf, val.length);
        this.length += val.length;
      } else {
        const length = this.length++;
        if (length === this.size) {
          this.resize();
        }
        const buf = this.clone();
        this.buf[0] = val;
        buf.copy(this.buf, 1, 0, length);
      }
    }
    append(val) {
      const length = this.length++;
      if (length === this.size) {
        this.resize();
      }
      this.buf[length] = val;
    }
    clone() {
      return Buffer2.from(this.buf.slice(0, this.length));
    }
    resize() {
      const length = this.length;
      this.size = this.size * 2;
      const buf = Buffer2.allocUnsafe(this.size);
      this.buf.copy(buf, 0, 0, length);
      this.buf = buf;
    }
    toString(encoding) {
      if (encoding) {
        return this.buf.slice(0, this.length).toString(encoding);
      } else {
        return Uint8Array.prototype.slice.call(this.buf.slice(0, this.length));
      }
    }
    toJSON() {
      return this.toString("utf8");
    }
    reset() {
      this.length = 0;
    }
  };
  var np = 12;
  var cr$1 = 13;
  var nl$1 = 10;
  var space = 32;
  var tab = 9;
  var init_state = function(options) {
    return {
      bomSkipped: false,
      bufBytesStart: 0,
      castField: options.cast_function,
      commenting: false,
      // Current error encountered by a record
      error: void 0,
      enabled: options.from_line === 1,
      escaping: false,
      escapeIsQuote: isBuffer(options.escape) && isBuffer(options.quote) && Buffer2.compare(options.escape, options.quote) === 0,
      // columns can be `false`, `true`, `Array`
      expectedRecordLength: Array.isArray(options.columns) ? options.columns.length : void 0,
      field: new ResizeableBuffer(20),
      firstLineToHeaders: options.cast_first_line_to_header,
      needMoreDataSize: Math.max(
        // Skip if the remaining buffer smaller than comment
        options.comment !== null ? options.comment.length : 0,
        ...options.delimiter.map((delimiter) => delimiter.length),
        // Skip if the remaining buffer can be escape sequence
        options.quote !== null ? options.quote.length : 0
      ),
      previousBuf: void 0,
      quoting: false,
      stop: false,
      rawBuffer: new ResizeableBuffer(100),
      record: [],
      recordHasError: false,
      record_length: 0,
      recordDelimiterMaxLength: options.record_delimiter.length === 0 ? 0 : Math.max(...options.record_delimiter.map((v) => v.length)),
      trimChars: [
        Buffer2.from(" ", options.encoding)[0],
        Buffer2.from("	", options.encoding)[0]
      ],
      wasQuoting: false,
      wasRowDelimiter: false,
      timchars: [
        Buffer2.from(Buffer2.from([cr$1], "utf8").toString(), options.encoding),
        Buffer2.from(Buffer2.from([nl$1], "utf8").toString(), options.encoding),
        Buffer2.from(Buffer2.from([np], "utf8").toString(), options.encoding),
        Buffer2.from(Buffer2.from([space], "utf8").toString(), options.encoding),
        Buffer2.from(Buffer2.from([tab], "utf8").toString(), options.encoding)
      ]
    };
  };
  var underscore = function(str) {
    return str.replace(/([A-Z])/g, function(_, match) {
      return "_" + match.toLowerCase();
    });
  };
  var normalize_options = function(opts) {
    const options = {};
    for (const opt in opts) {
      options[underscore(opt)] = opts[opt];
    }
    if (options.encoding === void 0 || options.encoding === true) {
      options.encoding = "utf8";
    } else if (options.encoding === null || options.encoding === false) {
      options.encoding = null;
    } else if (typeof options.encoding !== "string" && options.encoding !== null) {
      throw new CsvError(
        "CSV_INVALID_OPTION_ENCODING",
        [
          "Invalid option encoding:",
          "encoding must be a string or null to return a buffer,",
          `got ${JSON.stringify(options.encoding)}`
        ],
        options
      );
    }
    if (options.bom === void 0 || options.bom === null || options.bom === false) {
      options.bom = false;
    } else if (options.bom !== true) {
      throw new CsvError(
        "CSV_INVALID_OPTION_BOM",
        [
          "Invalid option bom:",
          "bom must be true,",
          `got ${JSON.stringify(options.bom)}`
        ],
        options
      );
    }
    options.cast_function = null;
    if (options.cast === void 0 || options.cast === null || options.cast === false || options.cast === "") {
      options.cast = void 0;
    } else if (typeof options.cast === "function") {
      options.cast_function = options.cast;
      options.cast = true;
    } else if (options.cast !== true) {
      throw new CsvError(
        "CSV_INVALID_OPTION_CAST",
        [
          "Invalid option cast:",
          "cast must be true or a function,",
          `got ${JSON.stringify(options.cast)}`
        ],
        options
      );
    }
    if (options.cast_date === void 0 || options.cast_date === null || options.cast_date === false || options.cast_date === "") {
      options.cast_date = false;
    } else if (options.cast_date === true) {
      options.cast_date = function(value) {
        const date2 = Date.parse(value);
        return !isNaN(date2) ? new Date(date2) : value;
      };
    } else if (typeof options.cast_date !== "function") {
      throw new CsvError(
        "CSV_INVALID_OPTION_CAST_DATE",
        [
          "Invalid option cast_date:",
          "cast_date must be true or a function,",
          `got ${JSON.stringify(options.cast_date)}`
        ],
        options
      );
    }
    options.cast_first_line_to_header = null;
    if (options.columns === true) {
      options.cast_first_line_to_header = void 0;
    } else if (typeof options.columns === "function") {
      options.cast_first_line_to_header = options.columns;
      options.columns = true;
    } else if (Array.isArray(options.columns)) {
      options.columns = normalize_columns_array(options.columns);
    } else if (options.columns === void 0 || options.columns === null || options.columns === false) {
      options.columns = false;
    } else {
      throw new CsvError(
        "CSV_INVALID_OPTION_COLUMNS",
        [
          "Invalid option columns:",
          "expect an array, a function or true,",
          `got ${JSON.stringify(options.columns)}`
        ],
        options
      );
    }
    if (options.group_columns_by_name === void 0 || options.group_columns_by_name === null || options.group_columns_by_name === false) {
      options.group_columns_by_name = false;
    } else if (options.group_columns_by_name !== true) {
      throw new CsvError(
        "CSV_INVALID_OPTION_GROUP_COLUMNS_BY_NAME",
        [
          "Invalid option group_columns_by_name:",
          "expect an boolean,",
          `got ${JSON.stringify(options.group_columns_by_name)}`
        ],
        options
      );
    } else if (options.columns === false) {
      throw new CsvError(
        "CSV_INVALID_OPTION_GROUP_COLUMNS_BY_NAME",
        [
          "Invalid option group_columns_by_name:",
          "the `columns` mode must be activated."
        ],
        options
      );
    }
    if (options.comment === void 0 || options.comment === null || options.comment === false || options.comment === "") {
      options.comment = null;
    } else {
      if (typeof options.comment === "string") {
        options.comment = Buffer2.from(options.comment, options.encoding);
      }
      if (!isBuffer(options.comment)) {
        throw new CsvError(
          "CSV_INVALID_OPTION_COMMENT",
          [
            "Invalid option comment:",
            "comment must be a buffer or a string,",
            `got ${JSON.stringify(options.comment)}`
          ],
          options
        );
      }
    }
    if (options.comment_no_infix === void 0 || options.comment_no_infix === null || options.comment_no_infix === false) {
      options.comment_no_infix = false;
    } else if (options.comment_no_infix !== true) {
      throw new CsvError(
        "CSV_INVALID_OPTION_COMMENT",
        [
          "Invalid option comment_no_infix:",
          "value must be a boolean,",
          `got ${JSON.stringify(options.comment_no_infix)}`
        ],
        options
      );
    }
    const delimiter_json = JSON.stringify(options.delimiter);
    if (!Array.isArray(options.delimiter))
      options.delimiter = [options.delimiter];
    if (options.delimiter.length === 0) {
      throw new CsvError(
        "CSV_INVALID_OPTION_DELIMITER",
        [
          "Invalid option delimiter:",
          "delimiter must be a non empty string or buffer or array of string|buffer,",
          `got ${delimiter_json}`
        ],
        options
      );
    }
    options.delimiter = options.delimiter.map(function(delimiter) {
      if (delimiter === void 0 || delimiter === null || delimiter === false) {
        return Buffer2.from(",", options.encoding);
      }
      if (typeof delimiter === "string") {
        delimiter = Buffer2.from(delimiter, options.encoding);
      }
      if (!isBuffer(delimiter) || delimiter.length === 0) {
        throw new CsvError(
          "CSV_INVALID_OPTION_DELIMITER",
          [
            "Invalid option delimiter:",
            "delimiter must be a non empty string or buffer or array of string|buffer,",
            `got ${delimiter_json}`
          ],
          options
        );
      }
      return delimiter;
    });
    if (options.escape === void 0 || options.escape === true) {
      options.escape = Buffer2.from('"', options.encoding);
    } else if (typeof options.escape === "string") {
      options.escape = Buffer2.from(options.escape, options.encoding);
    } else if (options.escape === null || options.escape === false) {
      options.escape = null;
    }
    if (options.escape !== null) {
      if (!isBuffer(options.escape)) {
        throw new Error(
          `Invalid Option: escape must be a buffer, a string or a boolean, got ${JSON.stringify(options.escape)}`
        );
      }
    }
    if (options.from === void 0 || options.from === null) {
      options.from = 1;
    } else {
      if (typeof options.from === "string" && /\d+/.test(options.from)) {
        options.from = parseInt(options.from);
      }
      if (Number.isInteger(options.from)) {
        if (options.from < 0) {
          throw new Error(
            `Invalid Option: from must be a positive integer, got ${JSON.stringify(opts.from)}`
          );
        }
      } else {
        throw new Error(
          `Invalid Option: from must be an integer, got ${JSON.stringify(options.from)}`
        );
      }
    }
    if (options.from_line === void 0 || options.from_line === null) {
      options.from_line = 1;
    } else {
      if (typeof options.from_line === "string" && /\d+/.test(options.from_line)) {
        options.from_line = parseInt(options.from_line);
      }
      if (Number.isInteger(options.from_line)) {
        if (options.from_line <= 0) {
          throw new Error(
            `Invalid Option: from_line must be a positive integer greater than 0, got ${JSON.stringify(opts.from_line)}`
          );
        }
      } else {
        throw new Error(
          `Invalid Option: from_line must be an integer, got ${JSON.stringify(opts.from_line)}`
        );
      }
    }
    if (options.ignore_last_delimiters === void 0 || options.ignore_last_delimiters === null) {
      options.ignore_last_delimiters = false;
    } else if (typeof options.ignore_last_delimiters === "number") {
      options.ignore_last_delimiters = Math.floor(options.ignore_last_delimiters);
      if (options.ignore_last_delimiters === 0) {
        options.ignore_last_delimiters = false;
      }
    } else if (typeof options.ignore_last_delimiters !== "boolean") {
      throw new CsvError(
        "CSV_INVALID_OPTION_IGNORE_LAST_DELIMITERS",
        [
          "Invalid option `ignore_last_delimiters`:",
          "the value must be a boolean value or an integer,",
          `got ${JSON.stringify(options.ignore_last_delimiters)}`
        ],
        options
      );
    }
    if (options.ignore_last_delimiters === true && options.columns === false) {
      throw new CsvError(
        "CSV_IGNORE_LAST_DELIMITERS_REQUIRES_COLUMNS",
        [
          "The option `ignore_last_delimiters`",
          "requires the activation of the `columns` option"
        ],
        options
      );
    }
    if (options.info === void 0 || options.info === null || options.info === false) {
      options.info = false;
    } else if (options.info !== true) {
      throw new Error(
        `Invalid Option: info must be true, got ${JSON.stringify(options.info)}`
      );
    }
    if (options.max_record_size === void 0 || options.max_record_size === null || options.max_record_size === false) {
      options.max_record_size = 0;
    } else if (Number.isInteger(options.max_record_size) && options.max_record_size >= 0) ;
    else if (typeof options.max_record_size === "string" && /\d+/.test(options.max_record_size)) {
      options.max_record_size = parseInt(options.max_record_size);
    } else {
      throw new Error(
        `Invalid Option: max_record_size must be a positive integer, got ${JSON.stringify(options.max_record_size)}`
      );
    }
    if (options.objname === void 0 || options.objname === null || options.objname === false) {
      options.objname = void 0;
    } else if (isBuffer(options.objname)) {
      if (options.objname.length === 0) {
        throw new Error(`Invalid Option: objname must be a non empty buffer`);
      }
      if (options.encoding === null) ;
      else {
        options.objname = options.objname.toString(options.encoding);
      }
    } else if (typeof options.objname === "string") {
      if (options.objname.length === 0) {
        throw new Error(`Invalid Option: objname must be a non empty string`);
      }
    } else if (typeof options.objname === "number") ;
    else {
      throw new Error(
        `Invalid Option: objname must be a string or a buffer, got ${options.objname}`
      );
    }
    if (options.objname !== void 0) {
      if (typeof options.objname === "number") {
        if (options.columns !== false) {
          throw Error(
            "Invalid Option: objname index cannot be combined with columns or be defined as a field"
          );
        }
      } else {
        if (options.columns === false) {
          throw Error(
            "Invalid Option: objname field must be combined with columns or be defined as an index"
          );
        }
      }
    }
    if (options.on_record === void 0 || options.on_record === null) {
      options.on_record = void 0;
    } else if (typeof options.on_record !== "function") {
      throw new CsvError(
        "CSV_INVALID_OPTION_ON_RECORD",
        [
          "Invalid option `on_record`:",
          "expect a function,",
          `got ${JSON.stringify(options.on_record)}`
        ],
        options
      );
    }
    if (options.on_skip !== void 0 && options.on_skip !== null && typeof options.on_skip !== "function") {
      throw new Error(
        `Invalid Option: on_skip must be a function, got ${JSON.stringify(options.on_skip)}`
      );
    }
    if (options.quote === null || options.quote === false || options.quote === "") {
      options.quote = null;
    } else {
      if (options.quote === void 0 || options.quote === true) {
        options.quote = Buffer2.from('"', options.encoding);
      } else if (typeof options.quote === "string") {
        options.quote = Buffer2.from(options.quote, options.encoding);
      }
      if (!isBuffer(options.quote)) {
        throw new Error(
          `Invalid Option: quote must be a buffer or a string, got ${JSON.stringify(options.quote)}`
        );
      }
    }
    if (options.raw === void 0 || options.raw === null || options.raw === false) {
      options.raw = false;
    } else if (options.raw !== true) {
      throw new Error(
        `Invalid Option: raw must be true, got ${JSON.stringify(options.raw)}`
      );
    }
    if (options.record_delimiter === void 0) {
      options.record_delimiter = [];
    } else if (typeof options.record_delimiter === "string" || isBuffer(options.record_delimiter)) {
      if (options.record_delimiter.length === 0) {
        throw new CsvError(
          "CSV_INVALID_OPTION_RECORD_DELIMITER",
          [
            "Invalid option `record_delimiter`:",
            "value must be a non empty string or buffer,",
            `got ${JSON.stringify(options.record_delimiter)}`
          ],
          options
        );
      }
      options.record_delimiter = [options.record_delimiter];
    } else if (!Array.isArray(options.record_delimiter)) {
      throw new CsvError(
        "CSV_INVALID_OPTION_RECORD_DELIMITER",
        [
          "Invalid option `record_delimiter`:",
          "value must be a string, a buffer or array of string|buffer,",
          `got ${JSON.stringify(options.record_delimiter)}`
        ],
        options
      );
    }
    options.record_delimiter = options.record_delimiter.map(function(rd, i2) {
      if (typeof rd !== "string" && !isBuffer(rd)) {
        throw new CsvError(
          "CSV_INVALID_OPTION_RECORD_DELIMITER",
          [
            "Invalid option `record_delimiter`:",
            "value must be a string, a buffer or array of string|buffer",
            `at index ${i2},`,
            `got ${JSON.stringify(rd)}`
          ],
          options
        );
      } else if (rd.length === 0) {
        throw new CsvError(
          "CSV_INVALID_OPTION_RECORD_DELIMITER",
          [
            "Invalid option `record_delimiter`:",
            "value must be a non empty string or buffer",
            `at index ${i2},`,
            `got ${JSON.stringify(rd)}`
          ],
          options
        );
      }
      if (typeof rd === "string") {
        rd = Buffer2.from(rd, options.encoding);
      }
      return rd;
    });
    if (typeof options.relax_column_count === "boolean") ;
    else if (options.relax_column_count === void 0 || options.relax_column_count === null) {
      options.relax_column_count = false;
    } else {
      throw new Error(
        `Invalid Option: relax_column_count must be a boolean, got ${JSON.stringify(options.relax_column_count)}`
      );
    }
    if (typeof options.relax_column_count_less === "boolean") ;
    else if (options.relax_column_count_less === void 0 || options.relax_column_count_less === null) {
      options.relax_column_count_less = false;
    } else {
      throw new Error(
        `Invalid Option: relax_column_count_less must be a boolean, got ${JSON.stringify(options.relax_column_count_less)}`
      );
    }
    if (typeof options.relax_column_count_more === "boolean") ;
    else if (options.relax_column_count_more === void 0 || options.relax_column_count_more === null) {
      options.relax_column_count_more = false;
    } else {
      throw new Error(
        `Invalid Option: relax_column_count_more must be a boolean, got ${JSON.stringify(options.relax_column_count_more)}`
      );
    }
    if (typeof options.relax_quotes === "boolean") ;
    else if (options.relax_quotes === void 0 || options.relax_quotes === null) {
      options.relax_quotes = false;
    } else {
      throw new Error(
        `Invalid Option: relax_quotes must be a boolean, got ${JSON.stringify(options.relax_quotes)}`
      );
    }
    if (typeof options.skip_empty_lines === "boolean") ;
    else if (options.skip_empty_lines === void 0 || options.skip_empty_lines === null) {
      options.skip_empty_lines = false;
    } else {
      throw new Error(
        `Invalid Option: skip_empty_lines must be a boolean, got ${JSON.stringify(options.skip_empty_lines)}`
      );
    }
    if (typeof options.skip_records_with_empty_values === "boolean") ;
    else if (options.skip_records_with_empty_values === void 0 || options.skip_records_with_empty_values === null) {
      options.skip_records_with_empty_values = false;
    } else {
      throw new Error(
        `Invalid Option: skip_records_with_empty_values must be a boolean, got ${JSON.stringify(options.skip_records_with_empty_values)}`
      );
    }
    if (typeof options.skip_records_with_error === "boolean") ;
    else if (options.skip_records_with_error === void 0 || options.skip_records_with_error === null) {
      options.skip_records_with_error = false;
    } else {
      throw new Error(
        `Invalid Option: skip_records_with_error must be a boolean, got ${JSON.stringify(options.skip_records_with_error)}`
      );
    }
    if (options.rtrim === void 0 || options.rtrim === null || options.rtrim === false) {
      options.rtrim = false;
    } else if (options.rtrim !== true) {
      throw new Error(
        `Invalid Option: rtrim must be a boolean, got ${JSON.stringify(options.rtrim)}`
      );
    }
    if (options.ltrim === void 0 || options.ltrim === null || options.ltrim === false) {
      options.ltrim = false;
    } else if (options.ltrim !== true) {
      throw new Error(
        `Invalid Option: ltrim must be a boolean, got ${JSON.stringify(options.ltrim)}`
      );
    }
    if (options.trim === void 0 || options.trim === null || options.trim === false) {
      options.trim = false;
    } else if (options.trim !== true) {
      throw new Error(
        `Invalid Option: trim must be a boolean, got ${JSON.stringify(options.trim)}`
      );
    }
    if (options.trim === true && opts.ltrim !== false) {
      options.ltrim = true;
    } else if (options.ltrim !== true) {
      options.ltrim = false;
    }
    if (options.trim === true && opts.rtrim !== false) {
      options.rtrim = true;
    } else if (options.rtrim !== true) {
      options.rtrim = false;
    }
    if (options.to === void 0 || options.to === null) {
      options.to = -1;
    } else {
      if (typeof options.to === "string" && /\d+/.test(options.to)) {
        options.to = parseInt(options.to);
      }
      if (Number.isInteger(options.to)) {
        if (options.to <= 0) {
          throw new Error(
            `Invalid Option: to must be a positive integer greater than 0, got ${JSON.stringify(opts.to)}`
          );
        }
      } else {
        throw new Error(
          `Invalid Option: to must be an integer, got ${JSON.stringify(opts.to)}`
        );
      }
    }
    if (options.to_line === void 0 || options.to_line === null) {
      options.to_line = -1;
    } else {
      if (typeof options.to_line === "string" && /\d+/.test(options.to_line)) {
        options.to_line = parseInt(options.to_line);
      }
      if (Number.isInteger(options.to_line)) {
        if (options.to_line <= 0) {
          throw new Error(
            `Invalid Option: to_line must be a positive integer greater than 0, got ${JSON.stringify(opts.to_line)}`
          );
        }
      } else {
        throw new Error(
          `Invalid Option: to_line must be an integer, got ${JSON.stringify(opts.to_line)}`
        );
      }
    }
    return options;
  };
  var isRecordEmpty = function(record) {
    return record.every(
      (field2) => field2 == null || field2.toString && field2.toString().trim() === ""
    );
  };
  var cr = 13;
  var nl = 10;
  var boms = {
    // Note, the following are equals:
    // Buffer.from("\ufeff")
    // Buffer.from([239, 187, 191])
    // Buffer.from('EFBBBF', 'hex')
    utf8: Buffer2.from([239, 187, 191]),
    // Note, the following are equals:
    // Buffer.from "\ufeff", 'utf16le
    // Buffer.from([255, 254])
    utf16le: Buffer2.from([255, 254])
  };
  var transform = function(original_options = {}) {
    const info = {
      bytes: 0,
      comment_lines: 0,
      empty_lines: 0,
      invalid_field_length: 0,
      lines: 1,
      records: 0
    };
    const options = normalize_options(original_options);
    return {
      info,
      original_options,
      options,
      state: init_state(options),
      __needMoreData: function(i2, bufLen, end) {
        if (end) return false;
        const { encoding, escape, quote } = this.options;
        const { quoting, needMoreDataSize, recordDelimiterMaxLength } = this.state;
        const numOfCharLeft = bufLen - i2 - 1;
        const requiredLength = Math.max(
          needMoreDataSize,
          // Skip if the remaining buffer smaller than record delimiter
          // If "record_delimiter" is yet to be discovered:
          // 1. It is equals to `[]` and "recordDelimiterMaxLength" equals `0`
          // 2. We set the length to windows line ending in the current encoding
          // Note, that encoding is known from user or bom discovery at that point
          // recordDelimiterMaxLength,
          recordDelimiterMaxLength === 0 ? Buffer2.from("\r\n", encoding).length : recordDelimiterMaxLength,
          // Skip if remaining buffer can be an escaped quote
          quoting ? (escape === null ? 0 : escape.length) + quote.length : 0,
          // Skip if remaining buffer can be record delimiter following the closing quote
          quoting ? quote.length + recordDelimiterMaxLength : 0
        );
        return numOfCharLeft < requiredLength;
      },
      // Central parser implementation
      parse: function(nextBuf, end, push, close) {
        const {
          bom,
          comment_no_infix,
          encoding,
          from_line,
          ltrim,
          max_record_size,
          raw,
          relax_quotes,
          rtrim,
          skip_empty_lines,
          to,
          to_line
        } = this.options;
        let { comment, escape, quote, record_delimiter } = this.options;
        const { bomSkipped, previousBuf, rawBuffer, escapeIsQuote } = this.state;
        let buf;
        if (previousBuf === void 0) {
          if (nextBuf === void 0) {
            close();
            return;
          } else {
            buf = nextBuf;
          }
        } else if (previousBuf !== void 0 && nextBuf === void 0) {
          buf = previousBuf;
        } else {
          buf = Buffer2.concat([previousBuf, nextBuf]);
        }
        if (bomSkipped === false) {
          if (bom === false) {
            this.state.bomSkipped = true;
          } else if (buf.length < 3) {
            if (end === false) {
              this.state.previousBuf = buf;
              return;
            }
          } else {
            for (const encoding2 in boms) {
              if (boms[encoding2].compare(buf, 0, boms[encoding2].length) === 0) {
                const bomLength = boms[encoding2].length;
                this.state.bufBytesStart += bomLength;
                buf = buf.slice(bomLength);
                this.options = normalize_options({
                  ...this.original_options,
                  encoding: encoding2
                });
                ({ comment, escape, quote } = this.options);
                break;
              }
            }
            this.state.bomSkipped = true;
          }
        }
        const bufLen = buf.length;
        let pos;
        for (pos = 0; pos < bufLen; pos++) {
          if (this.__needMoreData(pos, bufLen, end)) {
            break;
          }
          if (this.state.wasRowDelimiter === true) {
            this.info.lines++;
            this.state.wasRowDelimiter = false;
          }
          if (to_line !== -1 && this.info.lines > to_line) {
            this.state.stop = true;
            close();
            return;
          }
          if (this.state.quoting === false && record_delimiter.length === 0) {
            const record_delimiterCount = this.__autoDiscoverRecordDelimiter(
              buf,
              pos
            );
            if (record_delimiterCount) {
              record_delimiter = this.options.record_delimiter;
            }
          }
          const chr = buf[pos];
          if (raw === true) {
            rawBuffer.append(chr);
          }
          if ((chr === cr || chr === nl) && this.state.wasRowDelimiter === false) {
            this.state.wasRowDelimiter = true;
          }
          if (this.state.escaping === true) {
            this.state.escaping = false;
          } else {
            if (escape !== null && this.state.quoting === true && this.__isEscape(buf, pos, chr) && pos + escape.length < bufLen) {
              if (escapeIsQuote) {
                if (this.__isQuote(buf, pos + escape.length)) {
                  this.state.escaping = true;
                  pos += escape.length - 1;
                  continue;
                }
              } else {
                this.state.escaping = true;
                pos += escape.length - 1;
                continue;
              }
            }
            if (this.state.commenting === false && this.__isQuote(buf, pos)) {
              if (this.state.quoting === true) {
                const nextChr = buf[pos + quote.length];
                const isNextChrTrimable = rtrim && this.__isCharTrimable(buf, pos + quote.length);
                const isNextChrComment = comment !== null && this.__compareBytes(comment, buf, pos + quote.length, nextChr);
                const isNextChrDelimiter = this.__isDelimiter(
                  buf,
                  pos + quote.length,
                  nextChr
                );
                const isNextChrRecordDelimiter = record_delimiter.length === 0 ? this.__autoDiscoverRecordDelimiter(buf, pos + quote.length) : this.__isRecordDelimiter(nextChr, buf, pos + quote.length);
                if (escape !== null && this.__isEscape(buf, pos, chr) && this.__isQuote(buf, pos + escape.length)) {
                  pos += escape.length - 1;
                } else if (!nextChr || isNextChrDelimiter || isNextChrRecordDelimiter || isNextChrComment || isNextChrTrimable) {
                  this.state.quoting = false;
                  this.state.wasQuoting = true;
                  pos += quote.length - 1;
                  continue;
                } else if (relax_quotes === false) {
                  const err2 = this.__error(
                    new CsvError(
                      "CSV_INVALID_CLOSING_QUOTE",
                      [
                        "Invalid Closing Quote:",
                        `got "${String.fromCharCode(nextChr)}"`,
                        `at line ${this.info.lines}`,
                        "instead of delimiter, record delimiter, trimable character",
                        "(if activated) or comment"
                      ],
                      this.options,
                      this.__infoField()
                    )
                  );
                  if (err2 !== void 0) return err2;
                } else {
                  this.state.quoting = false;
                  this.state.wasQuoting = true;
                  this.state.field.prepend(quote);
                  pos += quote.length - 1;
                }
              } else {
                if (this.state.field.length !== 0) {
                  if (relax_quotes === false) {
                    const info2 = this.__infoField();
                    const bom2 = Object.keys(boms).map(
                      (b) => boms[b].equals(this.state.field.toString()) ? b : false
                    ).filter(Boolean)[0];
                    const err2 = this.__error(
                      new CsvError(
                        "INVALID_OPENING_QUOTE",
                        [
                          "Invalid Opening Quote:",
                          `a quote is found on field ${JSON.stringify(info2.column)} at line ${info2.lines}, value is ${JSON.stringify(this.state.field.toString(encoding))}`,
                          bom2 ? `(${bom2} bom)` : void 0
                        ],
                        this.options,
                        info2,
                        {
                          field: this.state.field
                        }
                      )
                    );
                    if (err2 !== void 0) return err2;
                  }
                } else {
                  this.state.quoting = true;
                  pos += quote.length - 1;
                  continue;
                }
              }
            }
            if (this.state.quoting === false) {
              const recordDelimiterLength = this.__isRecordDelimiter(
                chr,
                buf,
                pos
              );
              if (recordDelimiterLength !== 0) {
                const skipCommentLine = this.state.commenting && this.state.wasQuoting === false && this.state.record.length === 0 && this.state.field.length === 0;
                if (skipCommentLine) {
                  this.info.comment_lines++;
                } else {
                  if (this.state.enabled === false && this.info.lines + (this.state.wasRowDelimiter === true ? 1 : 0) >= from_line) {
                    this.state.enabled = true;
                    this.__resetField();
                    this.__resetRecord();
                    pos += recordDelimiterLength - 1;
                    continue;
                  }
                  if (skip_empty_lines === true && this.state.wasQuoting === false && this.state.record.length === 0 && this.state.field.length === 0) {
                    this.info.empty_lines++;
                    pos += recordDelimiterLength - 1;
                    continue;
                  }
                  this.info.bytes = this.state.bufBytesStart + pos;
                  const errField = this.__onField();
                  if (errField !== void 0) return errField;
                  this.info.bytes = this.state.bufBytesStart + pos + recordDelimiterLength;
                  const errRecord = this.__onRecord(push);
                  if (errRecord !== void 0) return errRecord;
                  if (to !== -1 && this.info.records >= to) {
                    this.state.stop = true;
                    close();
                    return;
                  }
                }
                this.state.commenting = false;
                pos += recordDelimiterLength - 1;
                continue;
              }
              if (this.state.commenting) {
                continue;
              }
              if (comment !== null && (comment_no_infix === false || this.state.record.length === 0 && this.state.field.length === 0)) {
                const commentCount = this.__compareBytes(comment, buf, pos, chr);
                if (commentCount !== 0) {
                  this.state.commenting = true;
                  continue;
                }
              }
              const delimiterLength = this.__isDelimiter(buf, pos, chr);
              if (delimiterLength !== 0) {
                this.info.bytes = this.state.bufBytesStart + pos;
                const errField = this.__onField();
                if (errField !== void 0) return errField;
                pos += delimiterLength - 1;
                continue;
              }
            }
          }
          if (this.state.commenting === false) {
            if (max_record_size !== 0 && this.state.record_length + this.state.field.length > max_record_size) {
              return this.__error(
                new CsvError(
                  "CSV_MAX_RECORD_SIZE",
                  [
                    "Max Record Size:",
                    "record exceed the maximum number of tolerated bytes",
                    `of ${max_record_size}`,
                    `at line ${this.info.lines}`
                  ],
                  this.options,
                  this.__infoField()
                )
              );
            }
          }
          const lappend = ltrim === false || this.state.quoting === true || this.state.field.length !== 0 || !this.__isCharTrimable(buf, pos);
          const rappend = rtrim === false || this.state.wasQuoting === false;
          if (lappend === true && rappend === true) {
            this.state.field.append(chr);
          } else if (rtrim === true && !this.__isCharTrimable(buf, pos)) {
            return this.__error(
              new CsvError(
                "CSV_NON_TRIMABLE_CHAR_AFTER_CLOSING_QUOTE",
                [
                  "Invalid Closing Quote:",
                  "found non trimable byte after quote",
                  `at line ${this.info.lines}`
                ],
                this.options,
                this.__infoField()
              )
            );
          } else {
            if (lappend === false) {
              pos += this.__isCharTrimable(buf, pos) - 1;
            }
            continue;
          }
        }
        if (end === true) {
          if (this.state.quoting === true) {
            const err2 = this.__error(
              new CsvError(
                "CSV_QUOTE_NOT_CLOSED",
                [
                  "Quote Not Closed:",
                  `the parsing is finished with an opening quote at line ${this.info.lines}`
                ],
                this.options,
                this.__infoField()
              )
            );
            if (err2 !== void 0) return err2;
          } else {
            if (this.state.wasQuoting === true || this.state.record.length !== 0 || this.state.field.length !== 0) {
              this.info.bytes = this.state.bufBytesStart + pos;
              const errField = this.__onField();
              if (errField !== void 0) return errField;
              const errRecord = this.__onRecord(push);
              if (errRecord !== void 0) return errRecord;
            } else if (this.state.wasRowDelimiter === true) {
              this.info.empty_lines++;
            } else if (this.state.commenting === true) {
              this.info.comment_lines++;
            }
          }
        } else {
          this.state.bufBytesStart += pos;
          this.state.previousBuf = buf.slice(pos);
        }
        if (this.state.wasRowDelimiter === true) {
          this.info.lines++;
          this.state.wasRowDelimiter = false;
        }
      },
      __onRecord: function(push) {
        const {
          columns,
          group_columns_by_name,
          encoding,
          info: info2,
          from: from2,
          relax_column_count,
          relax_column_count_less,
          relax_column_count_more,
          raw,
          skip_records_with_empty_values
        } = this.options;
        const { enabled, record } = this.state;
        if (enabled === false) {
          return this.__resetRecord();
        }
        const recordLength = record.length;
        if (columns === true) {
          if (skip_records_with_empty_values === true && isRecordEmpty(record)) {
            this.__resetRecord();
            return;
          }
          return this.__firstLineToColumns(record);
        }
        if (columns === false && this.info.records === 0) {
          this.state.expectedRecordLength = recordLength;
        }
        if (recordLength !== this.state.expectedRecordLength) {
          const err2 = columns === false ? new CsvError(
            "CSV_RECORD_INCONSISTENT_FIELDS_LENGTH",
            [
              "Invalid Record Length:",
              `expect ${this.state.expectedRecordLength},`,
              `got ${recordLength} on line ${this.info.lines}`
            ],
            this.options,
            this.__infoField(),
            {
              record
            }
          ) : new CsvError(
            "CSV_RECORD_INCONSISTENT_COLUMNS",
            [
              "Invalid Record Length:",
              `columns length is ${columns.length},`,
              // rename columns
              `got ${recordLength} on line ${this.info.lines}`
            ],
            this.options,
            this.__infoField(),
            {
              record
            }
          );
          if (relax_column_count === true || relax_column_count_less === true && recordLength < this.state.expectedRecordLength || relax_column_count_more === true && recordLength > this.state.expectedRecordLength) {
            this.info.invalid_field_length++;
            this.state.error = err2;
          } else {
            const finalErr = this.__error(err2);
            if (finalErr) return finalErr;
          }
        }
        if (skip_records_with_empty_values === true && isRecordEmpty(record)) {
          this.__resetRecord();
          return;
        }
        if (this.state.recordHasError === true) {
          this.__resetRecord();
          this.state.recordHasError = false;
          return;
        }
        this.info.records++;
        if (from2 === 1 || this.info.records >= from2) {
          const { objname } = this.options;
          if (columns !== false) {
            const obj = {};
            for (let i2 = 0, l = record.length; i2 < l; i2++) {
              if (columns[i2] === void 0 || columns[i2].disabled) continue;
              if (group_columns_by_name === true && obj[columns[i2].name] !== void 0) {
                if (Array.isArray(obj[columns[i2].name])) {
                  obj[columns[i2].name] = obj[columns[i2].name].concat(record[i2]);
                } else {
                  obj[columns[i2].name] = [obj[columns[i2].name], record[i2]];
                }
              } else {
                obj[columns[i2].name] = record[i2];
              }
            }
            if (raw === true || info2 === true) {
              const extRecord = Object.assign(
                { record: obj },
                raw === true ? { raw: this.state.rawBuffer.toString(encoding) } : {},
                info2 === true ? { info: this.__infoRecord() } : {}
              );
              const err2 = this.__push(
                objname === void 0 ? extRecord : [obj[objname], extRecord],
                push
              );
              if (err2) {
                return err2;
              }
            } else {
              const err2 = this.__push(
                objname === void 0 ? obj : [obj[objname], obj],
                push
              );
              if (err2) {
                return err2;
              }
            }
          } else {
            if (raw === true || info2 === true) {
              const extRecord = Object.assign(
                { record },
                raw === true ? { raw: this.state.rawBuffer.toString(encoding) } : {},
                info2 === true ? { info: this.__infoRecord() } : {}
              );
              const err2 = this.__push(
                objname === void 0 ? extRecord : [record[objname], extRecord],
                push
              );
              if (err2) {
                return err2;
              }
            } else {
              const err2 = this.__push(
                objname === void 0 ? record : [record[objname], record],
                push
              );
              if (err2) {
                return err2;
              }
            }
          }
        }
        this.__resetRecord();
      },
      __firstLineToColumns: function(record) {
        const { firstLineToHeaders } = this.state;
        try {
          const headers = firstLineToHeaders === void 0 ? record : firstLineToHeaders.call(null, record);
          if (!Array.isArray(headers)) {
            return this.__error(
              new CsvError(
                "CSV_INVALID_COLUMN_MAPPING",
                [
                  "Invalid Column Mapping:",
                  "expect an array from column function,",
                  `got ${JSON.stringify(headers)}`
                ],
                this.options,
                this.__infoField(),
                {
                  headers
                }
              )
            );
          }
          const normalizedHeaders = normalize_columns_array(headers);
          this.state.expectedRecordLength = normalizedHeaders.length;
          this.options.columns = normalizedHeaders;
          this.__resetRecord();
          return;
        } catch (err2) {
          return err2;
        }
      },
      __resetRecord: function() {
        if (this.options.raw === true) {
          this.state.rawBuffer.reset();
        }
        this.state.error = void 0;
        this.state.record = [];
        this.state.record_length = 0;
      },
      __onField: function() {
        const { cast, encoding, rtrim, max_record_size } = this.options;
        const { enabled, wasQuoting } = this.state;
        if (enabled === false) {
          return this.__resetField();
        }
        let field2 = this.state.field.toString(encoding);
        if (rtrim === true && wasQuoting === false) {
          field2 = field2.trimRight();
        }
        if (cast === true) {
          const [err2, f] = this.__cast(field2);
          if (err2 !== void 0) return err2;
          field2 = f;
        }
        this.state.record.push(field2);
        if (max_record_size !== 0 && typeof field2 === "string") {
          this.state.record_length += field2.length;
        }
        this.__resetField();
      },
      __resetField: function() {
        this.state.field.reset();
        this.state.wasQuoting = false;
      },
      __push: function(record, push) {
        const { on_record } = this.options;
        if (on_record !== void 0) {
          const info2 = this.__infoRecord();
          try {
            record = on_record.call(null, record, info2);
          } catch (err2) {
            return err2;
          }
          if (record === void 0 || record === null) {
            return;
          }
        }
        push(record);
      },
      // Return a tuple with the error and the casted value
      __cast: function(field2) {
        const { columns, relax_column_count } = this.options;
        const isColumns = Array.isArray(columns);
        if (isColumns === true && relax_column_count && this.options.columns.length <= this.state.record.length) {
          return [void 0, void 0];
        }
        if (this.state.castField !== null) {
          try {
            const info2 = this.__infoField();
            return [void 0, this.state.castField.call(null, field2, info2)];
          } catch (err2) {
            return [err2];
          }
        }
        if (this.__isFloat(field2)) {
          return [void 0, parseFloat(field2)];
        } else if (this.options.cast_date !== false) {
          const info2 = this.__infoField();
          return [void 0, this.options.cast_date.call(null, field2, info2)];
        }
        return [void 0, field2];
      },
      // Helper to test if a character is a space or a line delimiter
      __isCharTrimable: function(buf, pos) {
        const isTrim = (buf2, pos2) => {
          const { timchars } = this.state;
          loop1: for (let i2 = 0; i2 < timchars.length; i2++) {
            const timchar = timchars[i2];
            for (let j = 0; j < timchar.length; j++) {
              if (timchar[j] !== buf2[pos2 + j]) continue loop1;
            }
            return timchar.length;
          }
          return 0;
        };
        return isTrim(buf, pos);
      },
      // Keep it in case we implement the `cast_int` option
      // __isInt(value){
      //   // return Number.isInteger(parseInt(value))
      //   // return !isNaN( parseInt( obj ) );
      //   return /^(\-|\+)?[1-9][0-9]*$/.test(value)
      // }
      __isFloat: function(value) {
        return value - parseFloat(value) + 1 >= 0;
      },
      __compareBytes: function(sourceBuf, targetBuf, targetPos, firstByte) {
        if (sourceBuf[0] !== firstByte) return 0;
        const sourceLength = sourceBuf.length;
        for (let i2 = 1; i2 < sourceLength; i2++) {
          if (sourceBuf[i2] !== targetBuf[targetPos + i2]) return 0;
        }
        return sourceLength;
      },
      __isDelimiter: function(buf, pos, chr) {
        const { delimiter, ignore_last_delimiters } = this.options;
        if (ignore_last_delimiters === true && this.state.record.length === this.options.columns.length - 1) {
          return 0;
        } else if (ignore_last_delimiters !== false && typeof ignore_last_delimiters === "number" && this.state.record.length === ignore_last_delimiters - 1) {
          return 0;
        }
        loop1: for (let i2 = 0; i2 < delimiter.length; i2++) {
          const del = delimiter[i2];
          if (del[0] === chr) {
            for (let j = 1; j < del.length; j++) {
              if (del[j] !== buf[pos + j]) continue loop1;
            }
            return del.length;
          }
        }
        return 0;
      },
      __isRecordDelimiter: function(chr, buf, pos) {
        const { record_delimiter } = this.options;
        const recordDelimiterLength = record_delimiter.length;
        loop1: for (let i2 = 0; i2 < recordDelimiterLength; i2++) {
          const rd = record_delimiter[i2];
          const rdLength = rd.length;
          if (rd[0] !== chr) {
            continue;
          }
          for (let j = 1; j < rdLength; j++) {
            if (rd[j] !== buf[pos + j]) {
              continue loop1;
            }
          }
          return rd.length;
        }
        return 0;
      },
      __isEscape: function(buf, pos, chr) {
        const { escape } = this.options;
        if (escape === null) return false;
        const l = escape.length;
        if (escape[0] === chr) {
          for (let i2 = 0; i2 < l; i2++) {
            if (escape[i2] !== buf[pos + i2]) {
              return false;
            }
          }
          return true;
        }
        return false;
      },
      __isQuote: function(buf, pos) {
        const { quote } = this.options;
        if (quote === null) return false;
        const l = quote.length;
        for (let i2 = 0; i2 < l; i2++) {
          if (quote[i2] !== buf[pos + i2]) {
            return false;
          }
        }
        return true;
      },
      __autoDiscoverRecordDelimiter: function(buf, pos) {
        const { encoding } = this.options;
        const rds = [
          // Important, the windows line ending must be before mac os 9
          Buffer2.from("\r\n", encoding),
          Buffer2.from("\n", encoding),
          Buffer2.from("\r", encoding)
        ];
        loop: for (let i2 = 0; i2 < rds.length; i2++) {
          const l = rds[i2].length;
          for (let j = 0; j < l; j++) {
            if (rds[i2][j] !== buf[pos + j]) {
              continue loop;
            }
          }
          this.options.record_delimiter.push(rds[i2]);
          this.state.recordDelimiterMaxLength = rds[i2].length;
          return rds[i2].length;
        }
        return 0;
      },
      __error: function(msg) {
        const { encoding, raw, skip_records_with_error } = this.options;
        const err2 = typeof msg === "string" ? new Error(msg) : msg;
        if (skip_records_with_error) {
          this.state.recordHasError = true;
          if (this.options.on_skip !== void 0) {
            this.options.on_skip(
              err2,
              raw ? this.state.rawBuffer.toString(encoding) : void 0
            );
          }
          return void 0;
        } else {
          return err2;
        }
      },
      __infoDataSet: function() {
        return {
          ...this.info,
          columns: this.options.columns
        };
      },
      __infoRecord: function() {
        const { columns, raw, encoding } = this.options;
        return {
          ...this.__infoDataSet(),
          error: this.state.error,
          header: columns === true,
          index: this.state.record.length,
          raw: raw ? this.state.rawBuffer.toString(encoding) : void 0
        };
      },
      __infoField: function() {
        const { columns } = this.options;
        const isColumns = Array.isArray(columns);
        return {
          ...this.__infoRecord(),
          column: isColumns === true ? columns.length > this.state.record.length ? columns[this.state.record.length].name : null : this.state.record.length,
          quoting: this.state.wasQuoting
        };
      }
    };
  };
  var parse = function(data, opts = {}) {
    if (typeof data === "string") {
      data = Buffer2.from(data);
    }
    const records = opts && opts.objname ? {} : [];
    const parser4 = transform(opts);
    const push = (record) => {
      if (parser4.options.objname === void 0) records.push(record);
      else {
        records[record[0]] = record[1];
      }
    };
    const close = () => {
    };
    const err1 = parser4.parse(data, false, push, close);
    if (err1 !== void 0) throw err1;
    const err2 = parser4.parse(void 0, true, push, close);
    if (err2 !== void 0) throw err2;
    return records;
  };

  // src/import/sha1.ts
  function sha1(text3) {
    const bytes = [];
    for (const char of text3) {
      let cp = char.codePointAt(0);
      if (cp >= 55296 && cp <= 57343) cp = 65533;
      if (cp < 128) bytes.push(cp);
      else if (cp < 2048) bytes.push(192 | cp >>> 6, 128 | cp & 63);
      else if (cp < 65536) bytes.push(224 | cp >>> 12, 128 | cp >>> 6 & 63, 128 | cp & 63);
      else bytes.push(240 | cp >>> 18, 128 | cp >>> 12 & 63, 128 | cp >>> 6 & 63, 128 | cp & 63);
    }
    const bitLength = bytes.length * 8;
    bytes.push(128);
    while (bytes.length % 64 !== 56) bytes.push(0);
    const high = Math.floor(bitLength / 4294967296), low = bitLength >>> 0;
    for (const word of [high, low]) {
      bytes.push(word >>> 24 & 255, word >>> 16 & 255, word >>> 8 & 255, word & 255);
    }
    const rotate = (n, bits2) => n << bits2 | n >>> 32 - bits2;
    let h0 = 1732584193, h1 = 4023233417, h2 = 2562383102, h3 = 271733878, h4 = 3285377520;
    const words2 = new Int32Array(80);
    for (let offset = 0; offset < bytes.length; offset += 64) {
      for (let i2 = 0; i2 < 16; i2++) {
        const p = offset + i2 * 4;
        words2[i2] = bytes[p] << 24 | bytes[p + 1] << 16 | bytes[p + 2] << 8 | bytes[p + 3];
      }
      for (let i2 = 16; i2 < 80; i2++) words2[i2] = rotate(words2[i2 - 3] ^ words2[i2 - 8] ^ words2[i2 - 14] ^ words2[i2 - 16], 1);
      let a = h0, b = h1, c = h2, d = h3, e = h4;
      for (let i2 = 0; i2 < 80; i2++) {
        const f = i2 < 20 ? b & c | ~b & d : i2 < 40 ? b ^ c ^ d : i2 < 60 ? b & c | b & d | c & d : b ^ c ^ d;
        const k = i2 < 20 ? 1518500249 : i2 < 40 ? 1859775393 : i2 < 60 ? 2400959708 : 3395469782;
        const next = rotate(a, 5) + f + e + k + words2[i2] | 0;
        e = d;
        d = c;
        c = rotate(b, 30);
        b = a;
        a = next;
      }
      h0 = h0 + a | 0;
      h1 = h1 + b | 0;
      h2 = h2 + c | 0;
      h3 = h3 + d | 0;
      h4 = h4 + e | 0;
    }
    return [h0, h1, h2, h3, h4].map((n) => (n >>> 0).toString(16).padStart(8, "0")).join("");
  }

  // src/import/util.ts
  function parseAmount(input) {
    let v = input.trim().replace(/\s/g, "").replace(/[€$]/g, "");
    if (v.includes(",") && v.includes(".")) {
      if (v.lastIndexOf(",") > v.lastIndexOf(".")) v = v.replace(/\./g, "").replace(",", ".");
      else v = v.replace(/,/g, "");
    } else if (v.includes(",")) {
      v = v.replace(",", ".");
    }
    return v || "0";
  }
  function fullYear(y) {
    const n = parseInt(y, 10);
    return n < 100 ? 2e3 + n : n;
  }
  function parseDateFlexible(input) {
    const t = input.trim();
    if (/^\d{4}-\d{2}-\d{2}/.test(t)) return /* @__PURE__ */ new Date(`${t.slice(0, 10)}T00:00:00Z`);
    let m = t.match(/^(\d{1,2})\.(\d{1,2})\.(\d{2,4})/);
    if (m) return new Date(Date.UTC(fullYear(m[3]), +m[2] - 1, +m[1]));
    m = t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})/);
    if (m) return new Date(Date.UTC(fullYear(m[3]), +m[1] - 1, +m[2]));
    const fallback = new Date(t);
    return isNaN(fallback.getTime()) ? /* @__PURE__ */ new Date() : fallback;
  }
  function pick(row, candidates) {
    for (const c of candidates) if (row[c] !== void 0 && row[c].trim() !== "") return row[c].trim();
    return void 0;
  }

  // src/lib/texts.ts
  var texts = {
    unauthenticated: { en: "Please log in again.", de: "Bitte melde dich erneut an." },
    forbidden: { en: "This account has no access to Aresium.", de: "Dieses Konto hat keinen Zugang zu Aresium." },
    authUnavailable: {
      en: "Login service unavailable, try again in a minute.",
      de: "Anmeldedienst nicht erreichbar, versuch es in einer Minute noch einmal."
    },
    importRunning: { en: "An import is already running.", de: "Ein Import l\xE4uft bereits." },
    importTooLarge: { en: "Import exceeds the 25 MB request limit.", de: "Der Import \xFCberschreitet die Grenze von 25 MB pro Anfrage." },
    noFiles: { en: "Choose a .csv or .xml file to import.", de: "W\xE4hle eine .csv- oder .xml-Datei zum Importieren." },
    camtDocument: { en: "This file is not a CAMT bank statement.", de: "Diese Datei ist kein CAMT-Kontoauszug." },
    camtType: { en: "Use a CAMT.052 or CAMT.053 bank statement.", de: "Verwende einen Kontoauszug im Format CAMT.052 oder CAMT.053." },
    paypalColumns: { en: "Required columns are missing from the PayPal CSV file.", de: "In der PayPal-CSV-Datei fehlen erforderliche Spalten." },
    bankColumns: { en: "Required columns are missing from the VR Bank CSV file.", de: "In der VR-Bank-CSV-Datei fehlen erforderliche Spalten." },
    invalidFile: { en: "This file could not be read. Check the export and try again.", de: "Diese Datei konnte nicht gelesen werden. Pr\xFCfe den Export und versuch es noch einmal." },
    importFailed: { en: "This file could not be imported. Try again in a minute.", de: "Diese Datei konnte nicht importiert werden. Versuch es in einer Minute noch einmal." },
    "not found": { en: "Transaction not found.", de: "Buchung nicht gefunden." },
    "unknown category": { en: "Category not found.", de: "Kategorie nicht gefunden." },
    "no categories": { en: "Choose at least one category.", de: "W\xE4hle mindestens eine Kategorie." },
    categoryRequired: { en: "Choose a transaction and a category.", de: "W\xE4hle eine Buchung und eine Kategorie." },
    categoriesRequired: { en: "Choose a transaction and its categories.", de: "W\xE4hle eine Buchung und ihre Kategorien." },
    requestTooLarge: { en: "This request is too large.", de: "Diese Anfrage ist zu gro\xDF." },
    serverError: { en: "Something went wrong. Try again in a minute.", de: "Etwas ist schiefgegangen. Versuch es in einer Minute noch einmal." }
  };
  function text(key, language) {
    return texts[key][language];
  }
  var euros = new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
  var wholeNumbers = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 0 });

  // src/import/errors.ts
  var ImportFileError = class extends Error {
    constructor(key) {
      super(text(key, "en"));
      __publicField(this, "key", key);
    }
  };

  // src/import/vrbank-csv.ts
  var COLS = {
    ownIban: ["IBAN Auftragskonto", "Auftragskonto", "Kontonummer Auftragskonto"],
    booking: ["Buchungstag", "Buchung", "Buchungsdatum"],
    value: ["Valutadatum", "Wertstellung", "Valuta"],
    name: [
      "Name Zahlungsbeteiligter",
      "Beguenstigter/Zahlungspflichtiger",
      "Beg\xFCnstigter/Zahlungspflichtiger",
      "Auftraggeber/Empf\xE4nger",
      "Empf\xE4nger/Zahlungspflichtiger",
      "Zahlungsbeteiligter"
    ],
    bookingText: ["Buchungstext", "Buchungsart", "Umsatzart", "Vorgang"],
    purpose: ["Verwendungszweck", "Vorgang/Verwendungszweck", "Verwendungszweck 1"],
    amount: ["Betrag", "Umsatz", "Betrag (EUR)"],
    currency: ["Waehrung", "W\xE4hrung"],
    sign: ["Soll/Haben", "S/H", "Soll-/Haben", "Soll-/Habenkennzeichen"],
    balance: ["Saldo nach Buchung", "Saldo"]
  };
  function detectDelimiter(content) {
    const firstLine = content.split(/\r?\n/)[0] ?? "";
    return (firstLine.match(/;/g)?.length ?? 0) >= (firstLine.match(/,/g)?.length ?? 0) ? ";" : ",";
  }
  function parseVrBankCsv(content) {
    const rows = parse(content, {
      columns: true,
      delimiter: detectDelimiter(content),
      skip_empty_lines: true,
      bom: true,
      relax_column_count: true,
      trim: true
    });
    if (rows.length === 0) {
      return { source: "bank", account: { name: "VR Bank", currency: "EUR" }, transactions: [] };
    }
    const headers = Object.keys(rows[0]);
    const hasAmount = COLS.amount.some((c) => headers.includes(c));
    const hasDate = COLS.booking.some((c) => headers.includes(c));
    if (!hasAmount || !hasDate) {
      throw new ImportFileError("bankColumns");
    }
    let iban;
    let currency = "EUR";
    const transactions = [];
    for (const row of rows) {
      const rawAmount = pick(row, COLS.amount);
      if (rawAmount === void 0) continue;
      let amount2 = parseAmount(rawAmount);
      const sh = pick(row, COLS.sign);
      if (sh && /^(s|d|soll)/i.test(sh) && !amount2.startsWith("-")) amount2 = `-${amount2}`;
      iban = iban || pick(row, COLS.ownIban);
      const ccy = pick(row, COLS.currency) || "EUR";
      currency = ccy;
      const bookingDate2 = parseDateFlexible(pick(row, COLS.booking) ?? "");
      const valueRaw = pick(row, COLS.value);
      const purpose = pick(row, COLS.purpose) || pick(row, COLS.bookingText) || "(no description)";
      const counterparty = pick(row, COLS.name) || null;
      const balanceRaw = pick(row, COLS.balance);
      const externalId = sha1(`${bookingDate2.toISOString()}|${amount2}|${purpose}|${counterparty ?? ""}`).slice(0, 24);
      transactions.push({
        externalId,
        bookingDate: bookingDate2,
        valueDate: valueRaw ? parseDateFlexible(valueRaw) : null,
        amount: amount2,
        balance: balanceRaw ? parseAmount(balanceRaw) : null,
        currency: ccy,
        description: purpose,
        counterparty,
        raw: row
      });
    }
    return {
      source: "bank",
      account: { name: iban ? `VR Bank \u2022\u2022${iban.slice(-4)}` : "VR Bank", iban, currency },
      transactions
    };
  }

  // src/import/camt.ts
  var import_fast_xml_parser = __toESM(require_fxp(), 1);
  var parser = new import_fast_xml_parser.XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    parseTagValue: false
    // keep IBANs / amounts as strings
  });
  function arr(x2) {
    if (x2 === void 0 || x2 === null) return [];
    return Array.isArray(x2) ? x2 : [x2];
  }
  function textOf(node2) {
    if (node2 && typeof node2 === "object" && "#text" in node2) {
      return String(node2["#text"]);
    }
    return node2 == null ? "" : String(node2);
  }
  function parseCamt(xml2) {
    const doc = parser.parse(xml2);
    const root = doc.Document;
    if (!root) throw new ImportFileError("camtDocument");
    const container = root.BkToCstmrStmt || root.BkToCstmrAcctRpt;
    if (!container) throw new ImportFileError("camtType");
    const statements = arr(container.Stmt || container.Rpt);
    const transactions = [];
    let iban;
    let currency = "EUR";
    for (const stmt of statements) {
      iban = iban || stmt?.Acct?.Id?.IBAN;
      currency = stmt?.Acct?.Ccy || currency;
      for (const ntry of arr(stmt.Ntry)) {
        const isDebit = ntry.CdtDbtInd === "DBIT";
        const amount2 = `${isDebit ? "-" : ""}${parseAmount(textOf(ntry.Amt))}`;
        const ccy = ntry.Amt && typeof ntry.Amt === "object" ? ntry.Amt["@_Ccy"] : void 0;
        const bookingDate2 = new Date(ntry.BookgDt?.Dt || ntry.BookgDt?.DtTm || ntry.ValDt?.Dt);
        const valueDate = ntry.ValDt?.Dt ? new Date(ntry.ValDt.Dt) : null;
        const tx = arr(ntry.NtryDtls?.TxDtls)[0];
        const remittance2 = arr(tx?.RmtInf?.Ustrd).map(textOf).join(" ").trim() || textOf(ntry.AddtlNtryInf).trim() || "(no description)";
        const creditor = tx?.RltdPties?.Cdtr?.Nm;
        const debtor = tx?.RltdPties?.Dbtr?.Nm;
        const counterpartyRaw = (isDebit ? creditor : debtor) || creditor || debtor;
        const counterparty = counterpartyRaw ? String(counterpartyRaw) : null;
        const ref = ntry.AcctSvcrRef || tx?.Refs?.AcctSvcrRef || tx?.Refs?.EndToEndId || tx?.Refs?.TxId;
        const externalId = ref && ref !== "NOTPROVIDED" ? String(ref) : sha1(`${bookingDate2.toISOString()}|${amount2}|${remittance2}|${counterparty ?? ""}`).slice(0, 24);
        transactions.push({
          externalId,
          bookingDate: bookingDate2,
          valueDate,
          amount: amount2,
          currency: ccy || currency,
          description: remittance2,
          counterparty,
          raw: ntry
        });
      }
    }
    return {
      source: "bank",
      account: { name: iban ? `VR Bank \u2022\u2022${iban.slice(-4)}` : "VR Bank", iban, currency },
      transactions
    };
  }

  // src/import/paypal-csv.ts
  var COLS2 = {
    date: ["Date", "Datum"],
    name: ["Name"],
    type: ["Type", "Typ"],
    currency: ["Currency", "W\xE4hrung", "Waehrung"],
    net: ["Net", "Netto"],
    gross: ["Gross", "Brutto"],
    id: ["Transaction ID", "Transaktionscode", "Transaktions-ID"],
    impact: ["Auswirkung auf Guthaben", "Balance Impact"],
    from: ["From Email Address", "Absender E-Mail-Adresse"]
  };
  var SKIP_TYPES = /* @__PURE__ */ new Set([
    "Einbehaltung f\xFCr offene Autorisierung",
    "R\xFCckbuchung allgemeiner Einbehaltung",
    "General Authorization",
    "Reserve Hold",
    "Reserve Release"
  ]);
  var FUNDING_TYPE = /bankgutschrift auf paypal|bank deposit to pp account/i;
  function parsePaypalCsv(content) {
    const rows = parse(content, {
      columns: true,
      skip_empty_lines: true,
      bom: true,
      relax_column_count: true
    });
    if (rows.length === 0) {
      return { source: "paypal", account: { name: "PayPal", currency: "EUR" }, transactions: [] };
    }
    const headers = Object.keys(rows[0]);
    const hasId = COLS2.id.some((c) => headers.includes(c));
    const hasAmount = [...COLS2.net, ...COLS2.gross].some((c) => headers.includes(c));
    if (!hasId || !hasAmount) {
      throw new ImportFileError("paypalColumns");
    }
    let currency = "EUR";
    const transactions = [];
    for (const row of rows) {
      const id = pick(row, COLS2.id);
      if (!id) continue;
      const impact = pick(row, COLS2.impact) ?? "";
      const type = pick(row, COLS2.type) || "PayPal";
      if (impact === "Memo" || impact === "Memo Item") continue;
      if (SKIP_TYPES.has(type)) continue;
      const ccy = pick(row, COLS2.currency) || "EUR";
      currency = ccy;
      const name = pick(row, COLS2.name) || "";
      transactions.push({
        externalId: id,
        bookingDate: parseDateFlexible(pick(row, COLS2.date) ?? ""),
        amount: parseAmount(pick(row, COLS2.net) ?? pick(row, COLS2.gross) ?? "0"),
        currency: ccy,
        // Merchant name drives categorisation; fall back to the PayPal type. Bank-funding rows
        // always use the type: PayPal sometimes fills in the merchant's name on them, which
        // made merchant rules grab the top-up instead of the "Transfer" rule.
        description: FUNDING_TYPE.test(type) ? type : name || type,
        counterparty: name || pick(row, COLS2.from) || null,
        raw: row
      });
    }
    return { source: "paypal", account: { name: "PayPal", currency }, transactions };
  }

  // src/engine/readers/paypal.ts
  function parsePaypalCsv2(text3) {
    const file = parsePaypalCsv(text3);
    return {
      ...file,
      transactions: file.transactions.map((payment) => {
        const raw = payment.raw;
        if (pick(raw, ["Name"])) return payment;
        return { ...payment, counterparty: null, description: pick(raw, ["Type", "Typ", "Beschreibung"]) ?? payment.description };
      })
    };
  }

  // src/data/dashboard.ts
  var money = (n) => Math.round(n * 100) / 100;
  var UNSORTED = "Uncategorised";
  var isUnsorted = (categoryName) => !categoryName || categoryName === UNSORTED;
  var UNSORTED_META = { name: UNSORTED, icon: "CircleHelp", color: "#9ca3af", kind: "spend" };
  function buildDashboard(source) {
    const { months, categories, balanceByDay } = source;
    const catByName = new Map(categories.map((c) => [c.name, c]));
    const incomeKeep = /* @__PURE__ */ new Set(["Tax", ...categories.filter((c) => c.kind !== "spend").map((c) => c.name)]);
    const monthIndex = new Map(months.map((m, i2) => [m.key, i2]));
    const makeSeries = () => ({
      months: months.map(() => 0),
      days: Object.fromEntries(months.map((m) => [m.key, new Array(m.days).fill(0)]))
    });
    const spend = new Map(categories.map((c) => [c.name, makeSeries()]));
    const income = /* @__PURE__ */ new Map();
    const categoryAll = new Map(categories.map((c) => [c.name, 0]));
    const categoryMonths = months.map(() => new Map(categories.map((c) => [c.name, 0])));
    const incomeAll = /* @__PURE__ */ new Map();
    const incomeMonths = months.map(() => /* @__PURE__ */ new Map());
    const total = { expense: 0, income: 0, categories: [], incomeBuckets: [] };
    const byMonth = Object.fromEntries(months.map((mo) => {
      const dayBalance = Array.from({ length: mo.days }, (_, i2) => balanceByDay[`${mo.key}-${String(i2 + 1).padStart(2, "0")}`] ?? null);
      return [mo.key, {
        expense: 0,
        income: 0,
        categories: [],
        incomeBuckets: [],
        endBalance: balanceByDay[`${mo.key}-${String(mo.days).padStart(2, "0")}`] ?? null,
        dayExpense: new Array(mo.days).fill(0),
        dayExpenseRunning: [],
        dayIncome: new Array(mo.days).fill(0),
        dayBalance
      }];
    }));
    const add = (map, name, amount2) => map.set(name, (map.get(name) || 0) + amount2);
    const transactions = [];
    for (const t of source.transactions) {
      const month = t.date.slice(0, 7);
      const day2 = parseInt(t.date.slice(8), 10);
      const index = monthIndex.get(month);
      const mo = index === void 0 ? void 0 : byMonth[month];
      const validDay = !!mo && day2 >= 1 && day2 <= mo.dayExpense.length;
      const tags = t.tags || [];
      const covered = t.coveredBy !== void 0;
      const isTransfer = catByName.get(t.categoryName)?.kind === "transfer";
      const names2 = [.../* @__PURE__ */ new Set([t.categoryName, ...tags])].filter((name) => catByName.get(name)?.kind !== "transfer");
      const spending = !isTransfer && (t.amount < 0 || covered);
      const incoming = !isTransfer && t.amount > 0 && !covered;
      const amount2 = t.counted ?? t.amount;
      const categoriesIn = spending ? names2 : [];
      const buckets = incoming ? [...new Set(names2.map((name) => isUnsorted(name) ? UNSORTED : name))] : [];
      const txn = {
        id: t.id,
        date: t.date,
        day: day2,
        month,
        amount: t.amount,
        categoryName: t.categoryName,
        tags: [...tags],
        place: t.place,
        city: t.city,
        categoriesIn,
        incomeBuckets: buckets
      };
      if (t.receiptId !== void 0) txn.receiptId = t.receiptId;
      if (t.provisional) txn.provisional = true;
      if (covered) txn.coveredBy = [...t.coveredBy];
      if (t.cashWithdrawal) txn.cashWithdrawal = true;
      if (t.counted !== void 0 && t.counted !== t.amount) txn.counted = t.counted;
      if (t.paidBack !== void 0) txn.paidBack = t.paidBack;
      if (t.paidBackBy) txn.paidBackBy = t.paidBackBy.map((link) => ({ ...link }));
      if (t.paysBack) txn.paysBack = t.paysBack.map((link) => ({ ...link }));
      transactions.push(txn);
      if (spending) {
        total.expense += -amount2;
        if (mo) {
          mo.expense += -amount2;
          if (validDay) mo.dayExpense[day2 - 1] += -amount2;
        }
      }
      for (const name of categoriesIn) {
        const series = spend.get(name);
        if (!series) continue;
        add(categoryAll, name, -amount2);
        if (index !== void 0) {
          add(categoryMonths[index], name, -amount2);
          series.months[index] += -amount2;
          if (validDay) series.days[month][day2 - 1] += -amount2;
        }
      }
      if (incoming) {
        total.income += amount2;
        if (mo) {
          mo.income += amount2;
          if (validDay) mo.dayIncome[day2 - 1] += amount2;
        }
      }
      for (const bucket of buckets) {
        if (!income.has(bucket)) income.set(bucket, makeSeries());
        add(incomeAll, bucket, amount2);
        if (index !== void 0) {
          add(incomeMonths[index], bucket, amount2);
          const series = income.get(bucket);
          series.months[index] += amount2;
          if (validDay) series.days[month][day2 - 1] += amount2;
        }
      }
    }
    const categoryRows = (totals) => categories.filter((c) => c.kind !== "transfer").map((c) => ({ name: c.name, total: money(totals.get(c.name) ?? 0) })).filter((c) => c.total > 0).sort((a, b) => b.total - a.total);
    const incomeRows = (totals) => [...totals].map(([name, n]) => ({ name, total: money(n) })).filter((c) => c.total > 0).sort((a, b) => b.total - a.total);
    total.expense = money(total.expense);
    total.income = money(total.income);
    total.categories = categoryRows(categoryAll);
    total.incomeBuckets = incomeRows(incomeAll);
    months.forEach((m, i2) => {
      const mo = byMonth[m.key];
      mo.expense = money(mo.expense);
      mo.income = money(mo.income);
      let running = 0;
      mo.dayExpenseRunning = mo.dayExpense.map((v) => money(running += v));
      mo.dayExpense = mo.dayExpense.map(money);
      mo.dayIncome = mo.dayIncome.map(money);
      mo.categories = categoryRows(categoryMonths[i2]);
      mo.incomeBuckets = incomeRows(incomeMonths[i2]);
    });
    const roundSeries = (n) => money(Math.max(0, n));
    for (const map of [spend, income]) {
      for (const series of map.values()) {
        series.months = series.months.map(roundSeries);
        for (const m of months) series.days[m.key] = series.days[m.key].map(roundSeries);
      }
    }
    const ordered = (names2, order) => names2.slice().sort((a, b) => {
      const ia = order.indexOf(a), ib = order.indexOf(b);
      if (ia !== -1 && ib !== -1) return ia - ib;
      if (ia !== -1) return -1;
      if (ib !== -1) return 1;
      return a.localeCompare(b);
    });
    const databaseNames = new Set(source.databaseCategoryNames);
    const choices = categories.filter((c, i2) => databaseNames.has(c.name) && categories.findIndex((other) => other.name === c.name) === i2);
    const spendOrder = total.categories.map((r) => r.name);
    const incomeOrder = total.incomeBuckets.map((r) => r.name);
    const pick2 = {
      spend: [
        ...ordered(choices.filter((c) => c.kind === "spend").map((c) => c.name), spendOrder),
        ...ordered(choices.filter((c) => c.kind === "transfer").map((c) => c.name), incomeOrder),
        ...ordered(choices.filter((c) => c.kind === "income" && c.otherSide).map((c) => c.name), incomeOrder)
      ],
      income: [
        ...ordered(choices.filter((c) => incomeKeep.has(c.name)).map((c) => c.name), incomeOrder),
        ...ordered(choices.filter((c) => c.kind === "spend" && c.otherSide && !incomeKeep.has(c.name)).map((c) => c.name), spendOrder)
      ]
    };
    return {
      version: 2,
      months,
      categories,
      pick: pick2,
      incomeBuckets: [...income.keys()].map((name) => catByName.get(name) ?? (name === UNSORTED ? UNSORTED_META : void 0) ?? { name, icon: "Tag", color: "#34E27A", kind: "income" }),
      transactions,
      total,
      byMonth,
      spend: Object.fromEntries(spend),
      income: Object.fromEntries(income),
      overview: {
        expense: months.map((m) => byMonth[m.key].expense),
        income: months.map((m) => byMonth[m.key].income),
        balance: months.map((m) => byMonth[m.key].endBalance)
      },
      ...source.balanceUncertainDays?.length ? { balanceUncertainDays: source.balanceUncertainDays.map((day2) => ({ ...day2 })) } : {},
      ...source.cash ? { cash: source.cash } : {},
      ...source.paybacksIgnored?.length ? { paybacksIgnored: source.paybacksIgnored.map((link) => ({ ...link })) } : {}
    };
  }

  // src/engine/categories.ts
  var groups = [
    ["Everyday", "spend", [
      ["groceries", "Groceries", "Lebensmittel"],
      ["drugstore", "Drugstore", "Drogerie"],
      ["eating-out", "Eating out", "Essen gehen"],
      ["coffee-snacks", "Coffee & snacks", "Kaffee & Snacks"]
    ]],
    ["Home", "spend", [
      ["rent", "Rent", "Miete"],
      ["utilities", "Utilities", "Nebenkosten"],
      ["internet-phone", "Internet & phone", "Internet & Handy"],
      ["household", "Household", "Haushalt"],
      ["pets", "Pets", "Haustiere"]
    ]],
    ["Getting around", "spend", [
      ["bus-train", "Bus & train", "Bus & Bahn"],
      ["car-fuel", "Car & fuel", "Auto & Tanken"],
      ["taxi-sharing", "Taxi & sharing", "Taxi & Sharing"],
      ["travel", "Travel", "Reisen"]
    ]],
    ["Health & care", "spend", [
      ["health", "Health", "Gesundheit"],
      ["sports-fitness", "Sports & fitness", "Sport & Fitness"],
      ["personal-care", "Personal care", "K\xF6rperpflege"]
    ]],
    ["Free time", "spend", [
      ["going-out", "Going out", "Ausgehen"],
      ["entertainment", "Entertainment", "Unterhaltung"],
      ["hobbies", "Hobbies", "Hobbys"],
      ["subscriptions", "Subscriptions", "Abos"]
    ]],
    ["Shopping", "spend", [
      ["clothes", "Clothes", "Kleidung"],
      ["electronics", "Electronics", "Elektronik"],
      ["shopping", "Shopping", "Shopping"],
      ["gifts", "Gifts", "Geschenke"]
    ]],
    ["Study & work", "spend", [["education", "Education", "Bildung"], ["work", "Work", "Arbeit"]]],
    // "cash" holds the withdrawals: "Cash withdrawals" / "Abhebungen" since brief 32 (D9), so "Bargeld" is the Cash page.
    ["Money", "spend", [
      ["insurance", "Insurance", "Versicherungen"],
      ["taxes", "Taxes", "Steuern"],
      ["fees", "Fees", "Geb\xFChren"],
      ["memberships", "Memberships", "Mitgliedschaften"],
      ["donations", "Donations", "Spenden"],
      ["cash", "Cash withdrawals", "Abhebungen"],
      ["friends", "Friends", "Freunde"]
    ]],
    ["Money", "transfer", [["savings-investing", "Savings & investing", "Sparen & Anlegen"]]],
    ["Income", "income", [
      ["salary", "Salary & side jobs", "Gehalt & Nebenjob"],
      ["bafoeg-scholarships", "BAf\xF6G & scholarships", "BAf\xF6G & Stipendium"],
      ["parents-family", "Parents & family", "Eltern & Familie"],
      ["kindergeld", "Kindergeld", "Kindergeld"],
      ["selling-things", "Selling things", "Verk\xE4ufe"],
      ["interest-dividends", "Interest & dividends", "Zinsen & Dividenden"],
      ["other-income", "Other income", "Sonstige Einnahmen"]
    ]],
    ["Other", "spend", [["other", "Other", "Sonstiges"]]]
  ];
  var DEFAULT_CATEGORIES = groups.flatMap(([group, kind, entries]) => entries.map(([id, en, de]) => ({ id, name: { en, de }, group, kind })));
  var BUILT_IN_CATEGORIES = [
    { id: "own-transfers", name: { en: "Own transfers", de: "Eigene Umbuchungen" }, group: "Built in", kind: "transfer" },
    { id: "not-sorted", name: { en: "Not sorted", de: "Nicht sortiert" }, group: "Built in", kind: "spend" }
  ];
  var CATEGORY_LOOK = {
    "groceries": { icon: "ShoppingCart", color: "#26E07A" },
    "drugstore": { icon: "SprayCan", color: "#10DBAE" },
    "eating-out": { icon: "Utensils", color: "#FF7A33" },
    "coffee-snacks": { icon: "Coffee", color: "#E0A458" },
    "rent": { icon: "House", color: "#6366FF" },
    "utilities": { icon: "Zap", color: "#FFD23F" },
    "internet-phone": { icon: "Smartphone", color: "#4FC3F7" },
    "household": { icon: "Sofa", color: "#B388FF" },
    "pets": { icon: "PawPrint", color: "#FF9F80" },
    "bus-train": { icon: "TrainFront", color: "#13C8E8" },
    "car-fuel": { icon: "Fuel", color: "#F25F5C" },
    "taxi-sharing": { icon: "CarTaxiFront", color: "#FFC857" },
    "travel": { icon: "Plane", color: "#3B82F6" },
    "health": { icon: "Pill", color: "#FF4D6D" },
    "sports-fitness": { icon: "Dumbbell", color: "#34E27A" },
    "personal-care": { icon: "Scissors", color: "#FF7AD9" },
    "going-out": { icon: "Beer", color: "#FFC02E" },
    "entertainment": { icon: "Ticket", color: "#FF6B9A" },
    "hobbies": { icon: "Palette", color: "#9B8CFF" },
    "subscriptions": { icon: "Tv", color: "#A36BFF" },
    "clothes": { icon: "Shirt", color: "#FF5CC8" },
    "electronics": { icon: "Laptop", color: "#8FA0C4" },
    "shopping": { icon: "ShoppingBag", color: "#C77BFF" },
    "gifts": { icon: "Gift", color: "#FF5C8A" },
    "education": { icon: "GraduationCap", color: "#FFB020" },
    "work": { icon: "Briefcase", color: "#7C8DB5" },
    "insurance": { icon: "Shield", color: "#5B8CFF" },
    "taxes": { icon: "Receipt", color: "#E0894A" },
    "fees": { icon: "Landmark", color: "#94A3B8" },
    "memberships": { icon: "Handshake", color: "#3DA0FF" },
    "donations": { icon: "HandHeart", color: "#FF6F91" },
    "cash": { icon: "Banknote", color: "#6BCB77" },
    "friends": { icon: "Users", color: "#2BB0FF" },
    "savings-investing": { icon: "TrendingUp", color: "#25E0B0" },
    "salary": { icon: "Wallet", color: "#25E07A" },
    "bafoeg-scholarships": { icon: "BookOpen", color: "#84CC16" },
    "parents-family": { icon: "HeartHandshake", color: "#2BB0FF" },
    "kindergeld": { icon: "Baby", color: "#7DD3FC" },
    "selling-things": { icon: "Package", color: "#F59E0B" },
    "interest-dividends": { icon: "Percent", color: "#22C55E" },
    "other-income": { icon: "Coins", color: "#A3E635" },
    "other": { icon: "Ellipsis", color: "#9CA3AF" },
    "own-transfers": { icon: "Repeat", color: "#9AA6B8" },
    "not-sorted": { icon: "CircleHelp", color: "#9CA3AF" }
  };
  var CUSTOM_CATEGORY_LOOK = { icon: "Tag", color: "#9CA3AF" };
  var categoryLook = (id) => CATEGORY_LOOK[id] ?? CUSTOM_CATEGORY_LOOK;

  // src/engine/sorting/merchant.ts
  var citySuffix = /(?:[\s,/*-]+)(?:münchen|muenchen|berlin|hamburg|köln|koeln|frankfurt(?: am main)?|stuttgart|düsseldorf|duesseldorf|leipzig|dresden|hannover|nürnberg|nuernberg|bremen|heidelberg|mannheim|karlsruhe|augsburg|bonn|essen|dortmund)(?:\s+(?:de|deu|deutschland))?\s*$/u;
  function payeeText(payment) {
    return (payment.counterparty?.trim() || payment.description || payment.bookingText || "").toLowerCase().normalize("NFC");
  }
  function cardMerchant(text3) {
    const head = text3.toLowerCase().normalize("NFC").trim().match(
      /^(.+?)\s+[a-z]{3}\s+(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}\s+(?:(?:kurs\s*:?\s*\d|\d{1,3},\d{2}\s*%\s*auslandsums)[^\r\n]*?)?umsatz vom\s+\d{2}\.\d{2}\.\d{4}(?:\s+.*)?$/u
    )?.[1];
    if (!head) return null;
    const parts = head.match(/^(.+?)\s{2,}[a-z]{3}\s+(.+)$/u) ?? head.match(/^(.+)\s+[a-z]{3}\s+(\S+)$/u);
    return parts ? { merchant: parts[1].trim(), town: parts[2].trim() } : null;
  }
  var BOOKING_TYPE = /^(?:(?:sepa[ -])?(?:basis[ -]?)?lastschrift|kartenzahlung|debitkartenzahlung|kaufumsatz|sepa überweisung)\s*[:/-]?\s*/u;
  var SHOP_PROCESSOR_PREFIX = /^(?:paypal|sumup|spc|sq|iz|izettle|zettle|stripe|adyen|klarna|nexi|worldline)\s*[*_]\s*/iu;
  function sortingPayee(payment) {
    return payment.counterparty?.trim() || (payment.description || payment.bookingText || "").match(
      /^\s*empfänger:\s*(\S[^\r\n]*?)\s+kto\/iban:\s*[a-z]{2}\d{2}[a-z0-9]+\s+buchungstext:/iu
    )?.[1] || payeeText(payment);
  }
  function merchantKey(payment) {
    let text3 = payeeText(payment);
    text3 = cardMerchant(text3)?.merchant ?? text3;
    const processor = /^paypal(?:\s|$|\()/u;
    if (processor.test(text3)) {
      const details = (payment.description ?? payment.bookingText ?? "").toLowerCase().normalize("NFC");
      const seller = text3.match(/ihr einkauf bei\s+(.+?)(?:\.\s|$)/u)?.[1] ?? details.match(/ihr einkauf bei\s+(.+?)(?:\.\s|$)/u)?.[1] ?? text3.match(/^paypal\s*\*\s*(.+)/u)?.[1] ?? details.match(/^paypal\s*\*\s*(.+)/u)?.[1];
      if (!seller) return "";
      text3 = seller;
    }
    text3 = text3.replace(/^paypal\s*\*\s*/u, "");
    text3 = text3.replace(BOOKING_TYPE, "");
    text3 = text3.split(/\b(?:eref|mref|cred|iban|bic|mandatsreferenz|gläubiger-id|glaeubiger-id|kundenreferenz)\s*[:+]/u)[0];
    text3 = text3.replace(/\b(?:karte(?:nnr|nnummer)?|karten-nr|card(?: number)?|terminal|beleg|trace|folge-nr)\.?\s*[:#-]?\s*[\d*x.-]+/gu, " ");
    text3 = text3.replace(/\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b|\b\d{1,2}:\d{2}(?::\d{2})?\b/gu, " ");
    text3 = text3.replace(/\b(?:filiale|fil\.?|markt-nr\.?|branch)\s*[:#-]?\s*\d+\b/gu, " ");
    text3 = text3.replace(/\d{5,}|\b\d{3,}\b|\bx{2,}\d*\b|\*{2,}\d*/gu, " ");
    text3 = text3.replace(/^((?:rewe(?:\s+markt)?|dm(?:-drogerie\s*markt)?))\s+\d+\b/u, "$1 ");
    text3 = text3.replace(/\bsagt\s+danke\b|\bdankt\b/gu, " ");
    text3 = text3.replace(/\bgmbh\s*(?:&|\+|und)\s*co\.?\s*kg\b/gu, " ");
    text3 = text3.replace(/\b(?:gmbh|aktiengesellschaft|ag|se|kg|ohg)\b|\be\s*\.\s*k\b\s*\.?/gu, " ");
    text3 = text3.replace(/\b(?:und\s+)?co\b/gu, " ").replace(/&/gu, " ");
    text3 = text3.replace(/[\/;,|]+/gu, " ").replace(/\s+/gu, " ").replace(/[\s.*#-]+$/gu, "").trim();
    text3 = text3.replace(citySuffix, "").replace(/[\s.*#-]+$/gu, "").trim();
    return text3;
  }

  // src/engine/sorting/shop-words.ts
  var umlauts = { \u00E4: "ae", \u00F6: "oe", \u00FC: "ue", \u00DF: "ss" };
  var bareVowels = { \u00E4: "a", \u00F6: "o", \u00FC: "u", \u00DF: "ss" };
  function words(text3, letters) {
    const plain2 = text3.normalize("NFC").toLowerCase().replace(/[äöüß]/gu, (c) => letters[c]).normalize("NFD").replace(/\p{M}+/gu, "").replace(/ø/gu, "o").replace(/['’‘`´]/gu, "");
    return plain2.match(/[\p{L}\p{N}]+|[&+]/gu) ?? [];
  }
  function shopWords(text3) {
    return words(text3, umlauts);
  }
  function withoutShopReferences(text3) {
    return text3.replace(/\b(?:eref|mref|cred|kref|iban|bic|mandatsreferenz|mandatsref|gläubiger-id|glaeubiger-id|kundenreferenz)\s*[:+]\s*\S+/giu, " ");
  }
  var foodEndings = ["restaurant", "imbiss", "baeckerei", "cafe", "backstube", "hofladen"];
  function foodBusinessWord(word) {
    return foodEndings.find((ending) => word.length >= ending.length + 2 && word.endsWith(ending)) ?? null;
  }
  function businessWord(word) {
    if (/^grill(?:huette|hutte|haus|stube|imbiss|restaurant)$/u.test(word)) return "grill";
    if (/^kaffee(?:kontor|contor|haus|stube|bar|roesterei|rosterei)$/u.test(word)) return "cafe";
    if (/^(?:haar(?:werkstatt|studio|atelier|design)|hair(?:design|studio|styling|style|stylist))$/u.test(word)) return "friseur";
    if (/^lebensmittel(?:markt|laden|handel|geschaeft)$/u.test(word)) return "lebensmittel";
    if (word === "baumkuchenhaus") return "konditorei";
    return foodBusinessWord(word);
  }
  function businessFieldWords(text3) {
    const cleaned2 = withoutShopReferences(text3.trimEnd());
    const words2 = shopWords(cleaned2);
    const tail = words2.at(-1);
    if (cleaned2.endsWith(" ") || !tail || !/[\p{L}.…]\s*$/u.test(text3)) return words2;
    if (/^lebensmit(?:t(?:e(?:l)?)?)?$/u.test(tail)) words2[words2.length - 1] = "lebensmittel";
    if (/^hairst(?:y(?:l(?:e)?)?)?$/u.test(tail)) words2[words2.length - 1] = "hairstyle";
    if (/^podo(?:l(?:o(?:g(?:i(?:e)?)?)?)?)?$/u.test(tail) && /(?:^| )praxis (?:fuer|fur) podo[a-z]*$/u.test(words2.join(" "))) words2[words2.length - 1] = "podolog";
    return words2;
  }
  function shopSpellings(name, otherWords = /* @__PURE__ */ new Set()) {
    const spellings = [shopWords(name).join(" ")];
    if (/['’‘`´]/u.test(name)) spellings.push(shopWords(name.replace(/['’‘`´]/gu, " ")).join(" "));
    if (/[äöü]/iu.test(name)) {
      const plain2 = words(name, bareVowels).join(" ");
      if (!otherWords.has(plain2)) spellings.push(plain2);
      const blanks = shopWords(name.replace(/[äöü]/giu, " ")).join(" ");
      if (!otherWords.has(plain2) && blanks.replace(/[^a-z]/gu, "").length >= 5) spellings.push(blanks);
    }
    return [...new Set(spellings)].filter(Boolean);
  }

  // src/engine/sorting/towns.ts
  var SHOP_TOWNS = [
    "m\xFCnchen",
    "berlin",
    "hamburg",
    "k\xF6ln",
    "frankfurt",
    "frankfurt am main",
    "stuttgart",
    "d\xFCsseldorf",
    "leipzig",
    "dresden",
    "hannover",
    "n\xFCrnberg",
    "bremen",
    "heidelberg",
    "mannheim",
    "karlsruhe",
    "augsburg",
    "bonn",
    "essen",
    "dortmund"
  ];
  function townMatches(printed, town, cutoff = false) {
    const actual = shopWords(printed).join(" ");
    const normal = shopWords(town).join(" ");
    if (!actual || !normal) return false;
    const variants = [
      normal,
      normal.replace(/ae|oe|ue/gu, (pair) => pair[0]),
      normal.replace(/ae|oe|ue/gu, " ").replace(/\s+/gu, " ").trim()
    ];
    return variants.some((variant) => actual === variant || cutoff && actual.replaceAll(" ", "").length >= 7 && variant.startsWith(actual) && variant.length - actual.length <= 2);
  }

  // src/engine/sorting/shop-matcher.ts
  var moneyOf = (amount2) => typeof amount2 !== "number" || !Number.isFinite(amount2) || amount2 === 0 ? null : amount2 < 0 ? "out" : "in";
  var applies = (direction, money2) => money2 === null || direction === "both" || direction === money2;
  var branchNumber = /^(.+?[^\p{L}\p{N}])\d{2,6}(?![\p{L}\p{N}]|[.,:]\d)/u;
  function shopPayment(payment) {
    const clean2 = (text3) => text3.toLowerCase().trim().replace(BOOKING_TYPE, "").replace(SHOP_PROCESSOR_PREFIX, "");
    const recipient = sortingPayee(payment);
    return {
      ...payment,
      counterparty: recipient ? clean2(recipient) : payment.counterparty,
      description: payment.description ? clean2(payment.description) : payment.description,
      bookingText: payment.bookingText ? clean2(payment.bookingText) : payment.bookingText
    };
  }
  function compileShopList(list2) {
    const rules = [];
    const handWritten = /* @__PURE__ */ new Map(), brands = /* @__PURE__ */ new Map();
    const merchants = /* @__PURE__ */ new Map();
    const seen = /* @__PURE__ */ new Set();
    const otherWords = new Set(list2.plainVowelWords ?? []);
    const noBranches = new Set((list2.noBranches ?? []).flatMap((name) => shopSpellings(name, otherWords)));
    const compactOwners = /* @__PURE__ */ new Map();
    for (const [categoryId, names2] of [...list2.rules, ...list2.merchants, ...list2.brands]) for (const name of names2) {
      for (const spelling of shopSpellings(name, otherWords)) {
        const compact = spelling.replaceAll(" ", "");
        const owners = compactOwners.get(compact) ?? /* @__PURE__ */ new Set();
        owners.add(categoryId);
        compactOwners.set(compact, owners);
      }
    }
    const add = (index, name, categoryId, rank, direction, source) => {
      const spellings = shopSpellings(name, otherWords);
      if (source === "brand") for (const spelling of [...spellings]) {
        const compact = spelling.replaceAll(" ", "");
        if (/^[a-z]+(?: [a-z]+)+$/u.test(spelling) && compact.length >= 6 && compactOwners.get(compact)?.size === 1) {
          spellings.push(compact);
        }
      }
      for (const spelling of spellings) {
        if (seen.has(spelling)) continue;
        seen.add(spelling);
        const words2 = spelling.split(" ");
        const bucket = index.get(words2[0]) ?? [];
        bucket.push({ words: words2, categoryId, rank, direction, source });
        index.set(words2[0], bucket);
      }
    };
    for (const [categoryId, names2, direction = "both"] of list2.rules) for (const name of names2) {
      add(handWritten, name, categoryId, rules.length, direction, "rule");
      rules.push({ pattern: name, categoryId, source: "rule", direction });
    }
    for (const [categoryId, names2, direction = "both"] of list2.merchants) for (const name of names2) {
      for (const spelling of shopSpellings(name, otherWords)) {
        if (!merchants.has(spelling)) merchants.set(spelling, { categoryId, direction, name: spelling });
      }
      rules.push({ pattern: name, categoryId, source: "merchant", direction });
    }
    const specificity = (name) => [shopWords(name).length, shopWords(name).join("").length];
    const ranked = list2.brands.flatMap(([categoryId, names2]) => names2.map((name) => ({ name, categoryId, size: specificity(name) }))).sort((a, b) => b.size[0] - a.size[0] || b.size[1] - a.size[1] || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const { name, categoryId } of ranked) {
      add(brands, name, categoryId, rules.length, "both", "brand");
      rules.push({ pattern: name, categoryId, source: "brand", direction: "both" });
    }
    function find(index, words2) {
      const found = [];
      for (let start = 0; start < words2.length; start++) {
        const compound = index === handWritten ? businessWord(words2[start]) : null;
        const entries = [...index.get(words2[start]) ?? [], ...compound ? index.get(compound) ?? [] : []];
        for (const entry of entries) {
          const end = start + entry.words.length;
          if (end > words2.length) continue;
          let same = true;
          for (let j = 1; j < entry.words.length && same; j++) same = words2[start + j] === entry.words[j];
          if (same) found.push({ start, end, entry });
        }
      }
      return found;
    }
    function best(found, covering, money2) {
      let winner = null;
      for (const m of found) {
        if (!applies(m.entry.direction, money2)) continue;
        const inside = covering.some((o) => o.start <= m.start && o.end >= m.end && o.end - o.start > m.end - m.start);
        if (!inside && (!winner || m.entry.rank < winner.entry.rank)) winner = m;
      }
      if (!winner) return null;
      const { categoryId, words: words2, source, direction } = winner.entry;
      return { categoryId, name: words2.join(" "), source, direction, at: [winner.start, winner.end] };
    }
    function branchMerchant(payment) {
      const payee = payeeText(payment);
      const head = (cardMerchant(payee)?.merchant ?? payee).replace(BOOKING_TYPE, "").match(branchNumber)?.[1];
      const name = head === void 0 ? "" : shopWords(head).join(" ");
      return name && !noBranches.has(name) ? merchants.get(name) ?? null : null;
    }
    function townMerchant(payment, towns) {
      const card = cardMerchant(payeeText(payment)) ?? cardMerchant(payment.description ?? payment.bookingText ?? "");
      const name = shopWords(merchantKey(payment));
      const country = ["de", "deu", "deutschland"].includes(name.at(-1) ?? "");
      if (country) name.pop();
      const knownTowns = [...SHOP_TOWNS, ...towns, ...card ? [card.town] : []];
      const found = [];
      for (let cut = 1; cut < name.length; cut++) {
        const merchant = merchants.get(name.slice(0, cut).join(" "));
        if (!merchant) continue;
        const tail = name.slice(cut).join(" ");
        if (!knownTowns.some((town) => townMatches(tail, town, country || !!card))) continue;
        found.push(merchant);
      }
      return found.length && new Set(found.map((m) => m.categoryId)).size === 1 ? found[0] : null;
    }
    function decide(payment, towns = []) {
      const money2 = moneyOf(payment.amount);
      const details = payment.description ?? payment.bookingText ?? "";
      const payeeField = cardMerchant(payment.counterparty ?? "")?.merchant ?? payment.counterparty ?? "";
      const detailField = cardMerchant(details)?.merchant ?? details;
      const ruleWords = [...businessFieldWords(payeeField), ...businessFieldWords(detailField)];
      const written = find(handWritten, ruleWords);
      const rule = best(written, written, money2);
      if (rule) return rule;
      const shop = shopPayment(payment);
      const merchant = merchants.get(shopWords(merchantKey(shop)).join(" ")) ?? branchMerchant(shop) ?? townMerchant(shop, towns);
      if (merchant) {
        const { categoryId, direction, name } = merchant;
        return applies(direction, money2) ? { categoryId, name, source: "merchant", direction, at: null } : null;
      }
      const words2 = shopWords(withoutShopReferences(`${payeeField} ${detailField}`));
      const branded = find(brands, words2);
      return best(branded, [...written, ...branded], money2);
    }
    return {
      rules,
      match: (payment, towns) => decide(payment, towns)?.categoryId ?? null,
      find: decide
    };
  }

  // src/engine/sorting/shops.de.json
  var shops_de_default = {
    about: "Aresium's built-in shop list for Germany. Generated by scripts/build-shop-list.ts from scripts/shop-list.de.ts and the name-suggestion-index (nsi); do not edit by hand. Brand data \xA9 name-suggestion-index contributors, BSD-3-Clause (licence below).",
    nsi: {
      name: "name-suggestion-index",
      version: "8.0.20260918",
      generated: "2026-09-18T19:50:18.997Z",
      url: "https://cdn.jsdelivr.net/npm/name-suggestion-index@8.0.20260918/dist/json/nsi.min.json",
      sha256: "85752fb28977082f6e631636f1e9b8f97513947f75aaf1338c47ffa87207f513",
      homepage: "https://github.com/osmlab/name-suggestion-index",
      checked: "2026-10-27",
      licence: "BSD-3-Clause",
      licenceText: [
        "Copyright 2026, name-suggestion-index contributors",
        "Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:",
        "1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.",
        "2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.",
        "3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.",
        'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'
      ]
    },
    rules: [
      [
        "kindergeld",
        [
          "familienkasse",
          "kindergeld"
        ],
        "in"
      ],
      [
        "taxes",
        [
          "finanzamt",
          "steuerverwaltung"
        ],
        "both"
      ],
      [
        "taxes",
        [
          "steuererstattung"
        ],
        "in"
      ],
      [
        "taxes",
        [
          "einkommensteuer",
          "kirchensteuer",
          "grundsteuer",
          "hundesteuer",
          "gewerbesteuer",
          "zweitwohnungsteuer",
          "zweitwohnungssteuer",
          "steuernachzahlung",
          "steuervorauszahlung",
          "steuerberater",
          "steuerberatung",
          "lohnsteuerhilfe",
          "lohnsteuerhilfeverein"
        ],
        "out"
      ],
      [
        "bafoeg-scholarships",
        [
          "baf\xF6g",
          "bafoeg",
          "stipendium",
          "stipendien",
          "ausbildungsf\xF6rderung",
          "deutschlandstipendium",
          "studienstiftung",
          "begabtenf\xF6rderung",
          "daad",
          "erasmus+",
          "erasmus plus",
          "erasmus zuschuss",
          "erasmus f\xF6rderung"
        ],
        "in"
      ],
      [
        "salary",
        [
          "gehalt",
          "gehaltszahlung",
          "lohn",
          "lohnzahlung",
          "honorar",
          "bez\xFCge",
          "nettolohn",
          "nettogehalt",
          "lohnabrechnung",
          "gehaltsabrechnung",
          "entgeltabrechnung",
          "aushilfslohn",
          "verg\xFCtung",
          "ausbildungsverg\xFCtung",
          "verdienstabrechnung",
          "besoldung",
          "arbeitsentgelt",
          "landesamt f\xFCr finanzen",
          "landesamt f\xFCr besoldung",
          "bez\xFCgestelle"
        ],
        "in"
      ],
      [
        "own-transfers",
        [
          "eigen\xFCbertrag",
          "eigenuebertrag",
          "umbuchung",
          "bankgutschrift auf paypal",
          "bank deposit to pp account",
          "von nutzer eingeleitete abbuchung",
          "konto\xFCbertrag"
        ],
        "both"
      ],
      [
        "savings-investing",
        [
          "sparplan",
          "tagesgeld",
          "union investment",
          "uniondepot",
          "festgeld",
          "sparkonto",
          "sparbuch",
          "trade republic",
          "traderepublic",
          "scalable capital",
          "smartbroker",
          "justtrade",
          "finanzen.net zero",
          "flatex",
          "bitpanda",
          "coinbase",
          "binance",
          "wertpapierkauf",
          "wertpapierabrechnung",
          "etf",
          "deka investment",
          "verm\xF6genswirksame leistungen",
          "bausparkasse",
          "bausparvertrag",
          "bausparen"
        ],
        "both"
      ],
      [
        "interest-dividends",
        [
          "dividende",
          "dividenden",
          "zinsgutschrift",
          "habenzinsen",
          "zinsertrag",
          "ertragsaussch\xFCttung",
          "aussch\xFCttung"
        ],
        "in"
      ],
      [
        "selling-things",
        [
          "momox",
          "wirkaufens",
          "zoxs"
        ],
        "in"
      ],
      [
        "personal-care",
        [
          "haarschnitt"
        ],
        "out"
      ],
      [
        "household",
        [
          "m\xF6belkauf"
        ],
        "out"
      ],
      [
        "going-out",
        [
          "cocktails"
        ],
        "out"
      ],
      [
        "parents-family",
        [
          "unterst\xFCtzung von eltern",
          "unterhalt von eltern",
          "taschengeld von eltern",
          "unterst\xFCtzung von familie"
        ],
        "in"
      ],
      [
        "gifts",
        [
          "geschenk",
          "geburtstagsgeschenk",
          "weihnachtsgeschenk",
          "hochzeitsgeschenk"
        ],
        "both"
      ],
      [
        "other-income",
        [
          "mieteinnahme",
          "mieteinnahmen"
        ],
        "in"
      ],
      [
        "hobbies",
        [
          "r\xFCckzahlung buchkauf",
          "erstattung buchkauf"
        ],
        "in"
      ],
      [
        "work",
        [
          "b\xFCromaterial",
          "b\xFCrobedarf",
          "arbeitsmittel",
          "hosting beruflich"
        ],
        "out"
      ],
      [
        "subscriptions",
        [
          "film abo",
          "mail abo",
          "streaming abo"
        ],
        "both"
      ],
      [
        "other",
        [
          "bestattung",
          "bestattungshaus",
          "bestattungskosten",
          "beerdigungskosten"
        ],
        "out"
      ],
      [
        "friends",
        [
          "anteil gemeinsames abendessen",
          "anteil abendessen zur\xFCck"
        ],
        "both"
      ],
      [
        "subscriptions",
        [
          "netflix",
          "spotify",
          "disney+",
          "disney plus",
          "youtube premium",
          "amazon prime",
          "dazn",
          "audible",
          "icloud",
          "google one",
          "prime video",
          "primevideo",
          "youtube",
          "youtube music",
          "google storage",
          "apple.com/bill",
          "apple music",
          "apple tv",
          "itunes",
          "deezer",
          "tidal music",
          "sky deutschland",
          "sky ticket",
          "wow tv",
          "rtl+",
          "rtl plus",
          "joyn",
          "paramount+",
          "paramount plus",
          "magentatv",
          "waipu",
          "waipu.tv",
          "zattoo",
          "crunchyroll",
          "storytel",
          "bookbeat",
          "kindle unlimited",
          "readly",
          "blinkist",
          "duolingo",
          "babbel",
          "microsoft 365",
          "office 365",
          "adobe",
          "dropbox",
          "1password",
          "nordvpn",
          "expressvpn",
          "surfshark",
          "tinder",
          "bumble",
          "parship",
          "elitepartner",
          "linkedin premium",
          "xing premium",
          "playstation plus",
          "xbox game pass",
          "game pass",
          "nintendo switch online",
          "ea play",
          "zeit online",
          "zeit abo",
          "spiegel+",
          "spiegel plus",
          "s\xFCddeutsche zeitung",
          "faz.net",
          "handelsblatt",
          "bild+",
          "bildplus",
          "the economist"
        ],
        "both"
      ],
      [
        "eating-out",
        [
          "mcdonald",
          "mcdonalds",
          "mcdonald's",
          "mc donald's",
          "mc donalds",
          "burger king",
          "kfc",
          "subway",
          "vapiano",
          "nordsee filiale",
          "l'osteria",
          "losteria",
          "l osteria",
          "too good to go",
          "toogoodtogo",
          "hans im gl\xFCck",
          "dean & david",
          "five guys",
          "burgerista",
          "block house",
          "cafe del sol",
          "hard rock cafe",
          "cafe & bar celona",
          "celona"
        ],
        "both"
      ],
      [
        "eating-out",
        [
          "uber eats",
          "lieferando",
          "wolt",
          "foodora",
          "lieferheld",
          "pizza.de",
          "deliveroo"
        ],
        "out"
      ],
      [
        "eating-out",
        [
          "restaurant",
          "pizza",
          "pizzeria",
          "d\xF6ner",
          "doener",
          "kebab",
          "imbiss",
          "bistro",
          "mensa",
          "kebap",
          "ristorante",
          "trattoria",
          "osteria",
          "taverna",
          "gasthaus",
          "gasthof",
          "wirtshaus",
          "steakhouse",
          "sushi",
          "kantine",
          "cafeteria",
          "grill",
          "grillhaus",
          "grillrestaurant",
          "schnellrestaurant",
          "burrito",
          "burritos",
          "veggie",
          "vegan",
          "ramen",
          "pho",
          "poke",
          "bowl",
          "bowls",
          "noodle",
          "noodles",
          "falafel",
          "chicken",
          "mezedes",
          "kimchi",
          "simit",
          "spanferkel",
          "ratskeller",
          "brasserie",
          "burger",
          "onigiri",
          "street food",
          "thai food",
          "hot dog",
          "ocakba\u015F\u0131",
          "ocakbasi",
          "banh mi",
          "kitchen & wine",
          "kitchen and wine",
          "wine & dine",
          "wine and dine",
          "plat du jour"
        ],
        "out"
      ],
      [
        "taxi-sharing",
        [
          "share now",
          "sharenow",
          "miles mobility",
          "cambio carsharing",
          "cambio mobilit\xE4tsservice",
          "nextbike",
          "call a bike",
          "blacklane",
          "moia",
          "clevershuttle",
          "sixt share",
          "we share",
          "weshare",
          "flinkster",
          "stadtmobil",
          "book-n-drive",
          "teilauto",
          "greenwheels",
          "zipcar",
          "lime bike",
          "limebike",
          "lime scooter",
          "tier mobility",
          "tier operations",
          "voi technology",
          "voi scooters",
          "bird rides",
          "emmy sharing",
          "emmy-sharing",
          "db connect",
          "deutsche bahn connect",
          "stadtrad",
          "mvg rad",
          "swapfiets",
          "deezer nextbike",
          "ridedott"
        ],
        "both"
      ],
      [
        "taxi-sharing",
        [
          "uber trip",
          "uber bv",
          "uber technologies",
          "uber.com",
          "free now",
          "freenow",
          "bolt",
          "mytaxi",
          "blablacar",
          "getaround"
        ],
        "out"
      ],
      [
        "taxi-sharing",
        [
          "taxi",
          "taxi.eu",
          "taxizentrale",
          "funktaxi",
          "carsharing",
          "car-sharing"
        ],
        "out"
      ],
      [
        "coffee-snacks",
        [
          "backwerk",
          "ditsch",
          "starbucks",
          "coffee fellows",
          "le crobag",
          "back factory",
          "kamps",
          "gloria jean's"
        ],
        "both"
      ],
      [
        "coffee-snacks",
        [
          "b\xE4ckerei",
          "baeckerei",
          "caf\xE9",
          "cafe",
          "b\xE4cker",
          "backstube",
          "konditorei",
          "coffee",
          "espresso",
          "eiscaf\xE9",
          "eisdiele",
          "gelateria",
          "bakery",
          "boulangerie",
          "patisserie",
          "croissant",
          "croissants",
          "croissanterie",
          "brotmanufaktur",
          "backhaus",
          "kaffeer\xF6sterei",
          "caff\xE8",
          "gelato",
          "pasticceria",
          "waffle",
          "waffeln",
          "confiserie",
          "milchbar",
          "fladenbrot"
        ],
        "out"
      ],
      [
        "groceries",
        [
          "rewe",
          "edeka",
          "aldi",
          "lidl",
          "netto marken-discount",
          "netto markendiscount",
          "netto filiale",
          "netto fil",
          "netto sagt danke",
          "netto city",
          "netto stiftung",
          "netto supermarkt",
          "kaufland",
          "tegut",
          "hit fil",
          "interspar",
          "eurospar",
          "spar dankt",
          "spar markt",
          "denns",
          "dennree",
          "famila",
          "nahkauf",
          "e-center",
          "e center",
          "globus sb",
          "penny markt",
          "penny market",
          "penny sagt danke",
          "penny fil",
          "penny filiale",
          "norma filiale",
          "norma fil",
          "norma sagt danke",
          "norma lebensmittelfilialbetrieb",
          "real sb warenhaus",
          "real markt",
          "hit markt",
          "hit sb warenhaus",
          "hit handelsgruppe",
          "spar express",
          "spar supermarkt",
          "globus markthalle",
          "globus handelshof",
          "marktkauf",
          "vollcorner",
          "basic bio",
          "alnatura",
          "bio company",
          "knuspr",
          "hellofresh",
          "marley spoon",
          "bringmeister",
          "konsum dresden",
          "konsum leipzig",
          "nespresso"
        ],
        "both"
      ],
      [
        "groceries",
        [
          "goflink",
          "gorillas technologies",
          "getir"
        ],
        "out"
      ],
      [
        "groceries",
        [
          "getr\xE4nkemarkt",
          "metzgerei",
          "fleischerei",
          "supermarkt",
          "lebensmittel",
          "biomarkt",
          "bioladen",
          "wochenmarkt",
          "hofladen",
          "asiamarkt",
          "asia markt",
          "bauernhof",
          "feinkost",
          "helal markt",
          "tee contor"
        ],
        "out"
      ],
      [
        "drugstore",
        [
          "dm",
          "rossmann",
          "budni",
          "m\xFCller drogerie",
          "m\xFCller handels",
          "drogerie m\xFCller",
          "m\xFCller drogeriemarkt",
          "budnikowsky"
        ],
        "both"
      ],
      [
        "drugstore",
        [
          "drogeriemarkt",
          "drogerie",
          "naturdrogerie"
        ],
        "out"
      ],
      [
        "bus-train",
        [
          "mvg",
          "mvv",
          "bvg",
          "hvv",
          "db",
          "deutsche bahn",
          "db vertrieb",
          "db fernverkehr",
          "bahn.de",
          "flixbus",
          "flixtrain",
          "\xF6bb",
          "oebb",
          "kvb",
          "vvs",
          "rmv",
          "vrr",
          "vbb",
          "dvb",
          "lvb",
          "kvv",
          "vgn",
          "rnv",
          "vrn",
          "vrs",
          "vbn",
          "gvh",
          "nvv",
          "vvo",
          "mdv",
          "vmt",
          "rvv",
          "naldo",
          "nah.sh",
          "\xFCstra",
          "rheinbahn",
          "hochbahn",
          "ruhrbahn",
          "bogestra",
          "dsw21",
          "vgf",
          "bsag",
          "havag",
          "ssb ag",
          "stuttgarter stra\xDFenbahnen",
          "k\xF6lner verkehrs-betriebe",
          "db navigator",
          "db regio",
          "mvgo",
          "fairtiq",
          "trainline",
          "sbb",
          "sncf",
          "trenitalia",
          "westbahn",
          "metronom eisenbahn",
          "agilis",
          "go-ahead verkehrsgesellschaft",
          "national express rail",
          "abellio",
          "erixx",
          "vlexx",
          "nordwestbahn",
          "transdev",
          "bayerische regiobahn",
          "bayerische oberlandbahn",
          "l\xE4nderbahn",
          "odeg",
          "hessische landesbahn",
          "arverio",
          "sweg",
          "flixmobility",
          "blablacar bus"
        ],
        "both"
      ],
      [
        "bus-train",
        [
          "deutschlandticket",
          "verkehrsbetriebe",
          "verkehrsbetrieb",
          "verkehrsverbund",
          "verkehrsgesellschaft",
          "verkehrsgemeinschaft",
          "nahverkehr",
          "stadtbus",
          "stra\xDFenbahn",
          "s-bahn",
          "u-bahn",
          "regionalbus",
          "fernbus",
          "fahrkarte",
          "fahrkarten",
          "fahrschein",
          "fahrausweis",
          "monatskarte",
          "semesterticket",
          "deutschland-ticket",
          "d-ticket",
          "dticket",
          "bahncard"
        ],
        "out"
      ],
      [
        "car-fuel",
        [
          "autobahnen und schnellstra\xDFen finanzierungs aktiengesellschaft",
          "autobahnen und schnellstra\xDFen finanzierungs ag"
        ],
        "both"
      ],
      [
        "car-fuel",
        [
          "wirelane",
          "allego",
          "evbox",
          "leap24",
          "citywatt",
          "comfortcharge",
          "qwello",
          "reev",
          "e-flux",
          "ladeverbund+",
          "autostrom plus"
        ],
        "both"
      ],
      [
        "car-fuel",
        [
          "motors",
          "automobile",
          "autozentrum",
          "audi zentrum"
        ],
        "out"
      ],
      [
        "car-fuel",
        [
          "aral",
          "shell",
          "esso",
          "totalenergies",
          "jet tankstelle",
          "avia",
          "atu",
          "a.t.u",
          "easypark",
          "star tankstelle",
          "total tankstelle",
          "total station",
          "total service station",
          "jet station",
          "westfalen tankstelle",
          "raiffeisen tankstelle",
          "hem tankstelle",
          "q1 tankstelle",
          "kaufland tankstelle",
          "globus tankstelle",
          "edeka tankstelle",
          "marktkauf tankstelle",
          "famila tankstelle",
          "real tankstelle",
          "hit tankstelle",
          "agip",
          "apcoa",
          "contipark",
          "q-park",
          "paybyphone",
          "park now",
          "parknow",
          "evopark",
          "parkster",
          "asfinag",
          "enbw mobility",
          "e.on drive",
          "carglass",
          "bosch car service",
          "tesla supercharger"
        ],
        "both"
      ],
      [
        "car-fuel",
        [
          "tankstelle",
          "kfz-steuer",
          "kfz steuer",
          "autow\xE4sche",
          "autowaesche",
          "parkhaus",
          "parken",
          "parkgeb\xFChr",
          "parkgeb\xFChren",
          "parkticket",
          "parkschein",
          "parkplatz",
          "tiefgarage",
          "handyparken",
          "autohaus",
          "autowerkstatt",
          "kfz-werkstatt",
          "reifen",
          "reifenservice",
          "reifenwechsel",
          "waschanlage",
          "autowaschanlage",
          "waschstra\xDFe",
          "waschpark",
          "car wash",
          "carwash",
          "maut",
          "vignette",
          "ladestation",
          "gastankstelle",
          "tanke",
          "kfz meisterbetrieb"
        ],
        "out"
      ],
      [
        "travel",
        [
          "ryanair",
          "eurowings",
          "lufthansa",
          "easyjet",
          "sixt",
          "condor flugdienst",
          "condor flug",
          "condor.com",
          "tuifly",
          "tui fly",
          "wizz air",
          "wizzair",
          "vueling",
          "klm",
          "air france",
          "british airways",
          "swiss international air lines",
          "austrian airlines",
          "norwegian air",
          "turkish airlines",
          "pegasus airlines",
          "flypgs",
          "emirates",
          "qatar airways",
          "discover airlines",
          "transavia",
          "volotea",
          "aegean airlines",
          "ita airways",
          "iberia",
          "tap air portugal",
          "lot polish airlines",
          "sunexpress",
          "corendon",
          "air europa",
          "aer lingus",
          "finnair",
          "scandinavian airlines",
          "expedia",
          "opodo",
          "ebookers",
          "lastminute.com",
          "hotels.com",
          "hostelworld",
          "holidaycheck",
          "trivago",
          "omio",
          "getyourguide",
          "musement",
          "klook",
          "viator",
          "europcar",
          "enterprise rent-a-car",
          "hertz autovermietung",
          "avis autovermietung",
          "avis budget",
          "djh",
          "rewe reisen",
          "penny reisen",
          "lidl reisen",
          "aldi reisen",
          "netto reisen",
          "kaufland reisen",
          "leonardo boutique"
        ],
        "both"
      ],
      [
        "travel",
        [
          "booking.com",
          "airbnb",
          "fewo-direkt",
          "vrbo"
        ],
        "out"
      ],
      [
        "travel",
        [
          "bergbahn",
          "seilbahn",
          "hotel",
          "hostel",
          "jugendherberge",
          "ferienwohnung",
          "ferienhaus",
          "campingplatz",
          "camping",
          "reiseb\xFCro",
          "reisen",
          "flughafen",
          "airport",
          "airlines",
          "f\xE4hre",
          "ferry",
          "ferries",
          "skipass",
          "skilift",
          "bergbahnen",
          "kurtaxe",
          "umbuchung flug",
          "flug umbuchung",
          "apartmenthotel",
          "familienferienst\xE4tte"
        ],
        "out"
      ],
      [
        "rent",
        [
          "vonovia",
          "deutsche wohnen",
          "leg wohnen",
          "vivawest",
          "degewo",
          "gewobag",
          "howoge",
          "gesobau",
          "saga unternehmensgruppe",
          "gewofag",
          "grand city property",
          "adler group",
          "heimstaden",
          "akelius",
          "abg frankfurt holding",
          "nassauische heimst\xE4tte"
        ],
        "both"
      ],
      [
        "rent",
        [
          "kaltmiete",
          "warmmiete",
          "hausverwaltung",
          "miete",
          "mietzahlung",
          "wohnungsmiete",
          "mietzins",
          "untermiete",
          "zimmermiete",
          "mietkaution",
          "wohnheim",
          "wohnheimmiete",
          "studentenwohnheim",
          "wohnungsgenossenschaft",
          "wohnungsbaugenossenschaft",
          "wohnungsbaugesellschaft",
          "baugenossenschaft",
          "immobilienverwaltung",
          "wohnungsverwaltung"
        ],
        "out"
      ],
      [
        "utilities",
        [
          "e.on",
          "eon energie",
          "enbw",
          "vattenfall",
          "rwe",
          "eprimo",
          "yello strom",
          "ard zdf",
          "beitragsservice",
          "eon",
          "yello",
          "swm",
          "enercity",
          "mainova",
          "rheinenergie",
          "n-ergie",
          "swb vertrieb",
          "dew21",
          "drewag",
          "sachsenenergie",
          "entega",
          "badenova",
          "gasag",
          "enso energie",
          "e wie einfach",
          "lichtblick",
          "naturstrom",
          "polarstern energie",
          "tibber",
          "ostrom",
          "octopus energy",
          "gr\xFCnwelt",
          "extraenergie",
          "stromio",
          "maxenergy",
          "innogy",
          "energie s\xFCdbayern",
          "mvv energie",
          "techem",
          "ista deutschland",
          "minol",
          "brunata"
        ],
        "both"
      ],
      [
        "utilities",
        [
          "123energie",
          "allg\xE4uer \xFCberlandwerk",
          "avacon",
          "bayernwerk",
          "bigge energie",
          "bs energy",
          "e-regio",
          "e-werk mittelbaden",
          "eberwerk",
          "eins energie in sachsen",
          "emscher lippe energie",
          "energie calw",
          "energie saarlorlux",
          "energie und wasser potsdam",
          "energiedienst",
          "energis",
          "enviam",
          "envia mitteldeutsche energie",
          "fairenergie",
          "herzo werke",
          "inselwerke",
          "kreiswerke main-kinzig",
          "lechwerke",
          "lokalwerke",
          "lsw energie",
          "maingau",
          "mark-e",
          "naturenergie",
          "pfalzwerke",
          "regionalwerk bodensee",
          "rewag",
          "rh\xF6nenergie fulda",
          "stadtwerk am see",
          "stawag",
          "s\xFCwag",
          "teag th\xFCringer energie",
          "th\xFCringer energie",
          "wemag",
          "westenergie",
          "zeag energie"
        ],
        "both"
      ],
      [
        "utilities",
        [
          "stadtwerke",
          "gemeindewerke",
          "regionalwerk",
          "kreiswerke",
          "rundfunkbeitrag",
          "nebenkosten",
          "energieversorgung",
          "stromversorgung",
          "strom",
          "stromabschlag",
          "fernw\xE4rme",
          "wasserversorgung",
          "abwasser",
          "m\xFCllabfuhr",
          "abfallgeb\xFChr",
          "abfallgeb\xFChren",
          "m\xFCllgeb\xFChr",
          "m\xFCllgeb\xFChren",
          "betriebskosten",
          "heizkosten",
          "nebenkostenabrechnung",
          "nebenkostennachzahlung"
        ],
        "out"
      ],
      [
        "internet-phone",
        [
          "telekom",
          "vodafone",
          "o2",
          "telefonica",
          "1&1",
          "1und1",
          "congstar",
          "freenet",
          "sim.de",
          "simplytel",
          "blau mobilfunk",
          "telef\xF3nica",
          "drillisch",
          "winsim",
          "premiumsim",
          "smartmobil",
          "yourfone",
          "klarmobil",
          "mobilcom-debitel",
          "debitel",
          "otelo",
          "ay yildiz",
          "ayyildiz",
          "ortel mobile",
          "lebara",
          "lycamobile",
          "lyca mobile",
          "aldi talk",
          "lidl connect",
          "penny mobil",
          "edeka smart",
          "kaufland mobil",
          "netzclub",
          "fraenk",
          "ja! mobil",
          "norma connect",
          "tchibo mobil",
          "netcologne",
          "m-net",
          "pyur",
          "tele columbus",
          "unitymedia",
          "kabel deutschland",
          "deutsche glasfaser",
          "ewe tel",
          "wilhelm.tel",
          "versatel",
          "easybell",
          "sipgate",
          "starlink",
          "simyo",
          "blau.de",
          "t-mobile",
          "tele2",
          "telenor",
          "yourphone"
        ],
        "both"
      ],
      [
        "internet-phone",
        [
          "mobilfunk",
          "handyvertrag",
          "glasfaser",
          "internet festnetz",
          "festnetzanschluss"
        ],
        "out"
      ],
      [
        "insurance",
        [
          "allianz",
          "huk-coburg",
          "huk24",
          "axa",
          "ergo versicherung",
          "debeka",
          "signal iduna",
          "r+v",
          "barmer",
          "techniker krankenkasse",
          "aok",
          "huk",
          "dak",
          "dak-gesundheit",
          "kkh",
          "hkk",
          "sbk",
          "knappschaft",
          "viactiv",
          "hansemerkur",
          "continentale",
          "devk",
          "lvm",
          "vhv",
          "wgv",
          "hdi",
          "arag",
          "roland rechtsschutz",
          "provinzial",
          "sparkassenversicherung",
          "versicherungskammer",
          "die bayerische versicherung",
          "gothaer allgemeine",
          "n\xFCrnberger versicherung",
          "alte leipziger",
          "zurich versicherung",
          "zurich insurance",
          "generali",
          "cosmosdirekt",
          "barmenia",
          "universa",
          "mecklenburgische versicherung",
          "w\xFCrttembergische versicherung",
          "swiss life",
          "getsafe",
          "wefox",
          "ottonova",
          "hiscox",
          "helvetia",
          "baloise",
          "adac versicherung",
          "ergo direkt",
          "ergo group",
          "shell bkk",
          "big direkt gesund"
        ],
        "both"
      ],
      [
        "insurance",
        [
          "versicherung",
          "versicherungen",
          "versicherungs",
          "krankenkasse",
          "krankenversicherung",
          "haftpflicht",
          "haftpflichtversicherung",
          "hausratversicherung",
          "rechtsschutzversicherung",
          "lebensversicherung",
          "unfallversicherung",
          "berufsunf\xE4higkeitsversicherung",
          "kfz-versicherung",
          "autoversicherung",
          "reiseversicherung",
          "auslandskrankenversicherung",
          "zahnzusatzversicherung",
          "handyversicherung",
          "ikk",
          "bkk"
        ],
        "out"
      ],
      [
        "fees",
        [
          "kontof\xFChrung",
          "kontofuehrung",
          "kontof\xFChrungsgeb\xFChr",
          "kontofuehrungsgebuehr",
          "kartenentgelt",
          "kontoentgelt",
          "abschlussentgelt",
          "bankgeb\xFChren",
          "kontof\xFChrungsentgelt",
          "dispozinsen",
          "sollzinsen",
          "\xFCberziehungszinsen",
          "mahngeb\xFChr",
          "mahngeb\xFChren",
          "auslandseinsatzentgelt",
          "fremdw\xE4hrungsentgelt",
          "kartengeb\xFChr",
          "jahresgeb\xFChr",
          "jahresentgelt",
          "r\xFCcklastschriftgeb\xFChr",
          "verwahrentgelt"
        ],
        "out"
      ],
      [
        "cash",
        [
          "bargeldauszahlung",
          "bargeldabhebung",
          "geldautomat",
          "atm withdrawal",
          "cash withdrawal",
          "geldautomaten",
          "atm",
          "abhebung"
        ],
        "out"
      ],
      [
        "pets",
        [
          "fressnapf",
          "zooplus",
          "das futterhaus",
          "futterhaus",
          "zoo & co",
          "zoo zajac",
          "k\xF6lle zoo",
          "bitiba",
          "zooroyal",
          "petsdeli"
        ],
        "both"
      ],
      [
        "pets",
        [
          "tierarzt",
          "tierklinik",
          "tierarztpraxis",
          "kleintierpraxis",
          "tier\xE4rztin",
          "zoohandlung",
          "tierbedarf",
          "tiernahrung",
          "hundeschule",
          "hundefriseur"
        ],
        "out"
      ],
      [
        "household",
        [
          "ikea",
          "obi",
          "hornbach",
          "toom",
          "h\xF6ffner",
          "hoeffner",
          "xxxlutz",
          "m\xF6max",
          "moemax",
          "jysk",
          "bauhaus fachcentrum",
          "bauhaus e-business gesellschaft",
          "bauhaus gesellschaft",
          "bauhaus fil",
          "bauhaus filiale",
          "hellweg baumarkt",
          "hellweg die profi-baum\xE4rkte",
          "depot gries deco",
          "gries deco",
          "westwing",
          "wayfair",
          "zara home",
          "h&m home",
          "d\xE4nisches bettenlager",
          "porta m\xF6bel",
          "roller m\xF6bel",
          "poco einrichtungsm\xE4rkte",
          "poco einrichtungsmarkt",
          "poco dom\xE4ne"
        ],
        "both"
      ],
      [
        "household",
        [
          "baumarkt",
          "m\xF6belhaus",
          "m\xF6bel",
          "einrichtungshaus",
          "k\xFCchenstudio",
          "k\xFCchen",
          "matratzen",
          "bettenhaus",
          "gartencenter"
        ],
        "out"
      ],
      [
        "entertainment",
        [
          "cinemaxx",
          "cinestar",
          "uci kino",
          "kinopolis",
          "math\xE4ser",
          "mathaeser",
          "eventim",
          "ticketmaster",
          "yorck kino",
          "astor film lounge",
          "eventbrite",
          "reservix",
          "adticket",
          "tixforgigs",
          "dice.fm",
          "myticket",
          "oeticket",
          "see tickets",
          "europa-park",
          "phantasialand",
          "heide park",
          "movie park",
          "playstation",
          "playstation network",
          "sony interactive",
          "nintendo",
          "xbox",
          "steampowered",
          "epic games",
          "riot games",
          "blizzard entertainment",
          "gog.com",
          "gamestop",
          "allianz arena",
          "signal iduna park",
          "uber arena",
          "uber eats music hall",
          "vonovia ruhrstadion",
          "telekom dome",
          "o2 world",
          "o2 arena"
        ],
        "both"
      ],
      [
        "entertainment",
        [
          "fansale",
          "viagogo",
          "stubhub"
        ],
        "out"
      ],
      [
        "entertainment",
        [
          "kino",
          "kinos",
          "lichtspiele",
          "filmtheater",
          "filmpalast",
          "theater",
          "theatre",
          "staatsoper",
          "oper",
          "philharmonie",
          "konzerthaus",
          "konzert",
          "museum",
          "museen",
          "tierpark",
          "zoologischer garten",
          "wildpark",
          "freizeitpark",
          "bowling",
          "escape room",
          "lasertag",
          "laser tag",
          "minigolf",
          "trampolinpark",
          "therme"
        ],
        "out"
      ],
      [
        "hobbies",
        [
          "thalia b\xFCcher",
          "thalia buchhandlung",
          "just music",
          "idee creativmarkt",
          "modulor",
          "gerstaecker",
          "medimops",
          "buecher.de"
        ],
        "both"
      ],
      [
        "hobbies",
        [
          "musikhaus",
          "buchhandlung",
          "buchhaus",
          "modellbau",
          "books",
          "bookshop",
          "b\xFCcherladen"
        ],
        "out"
      ],
      [
        "health",
        [
          "docmorris",
          "shop apotheke",
          "medpex",
          "sanicare",
          "mycare",
          "aponeo",
          "eurapon",
          "apotal",
          "misterspex",
          "lensbest"
        ],
        "both"
      ],
      [
        "health",
        [
          "agaplesion",
          "ameos",
          "asklepios kliniken",
          "atos kliniken",
          "bg kliniken",
          "celenus kliniken",
          "gesundheitszentren rhein-neckar",
          "helios kliniken",
          "kmg kliniken",
          "median kliniken",
          "medical park",
          "mediclin",
          "paracelsus-kliniken",
          "rh\xF6n-klinikum",
          "sana kliniken",
          "sch\xF6n klinik",
          "vivantes"
        ],
        "out"
      ],
      [
        "health",
        [
          "apotheke",
          "arztpraxis",
          "gemeinschaftspraxis",
          "salzgrotte",
          "zahnarzt",
          "podolog",
          "physiotherapie",
          "klinik",
          "kontaktlinsen",
          "sanit\xE4tshaus",
          "brillen",
          "arzt",
          "\xE4rztin",
          "\xE4rzte",
          "hausarzt",
          "hausarztpraxis",
          "facharzt",
          "frauenarzt",
          "hautarzt",
          "augenarzt",
          "kinderarzt",
          "orthop\xE4de",
          "orthop\xE4die",
          "zahn\xE4rztin",
          "zahnarztpraxis",
          "kieferorthop\xE4die",
          "kieferorthop\xE4de",
          "zahnklinik",
          "praxis dr",
          "dr med",
          "mvz",
          "medizinisches versorgungszentrum",
          "klinikum",
          "krankenhaus",
          "uniklinik",
          "universit\xE4tsklinikum",
          "physiotherapeut",
          "physio",
          "ergotherapie",
          "logop\xE4die",
          "osteopathie",
          "osteopath",
          "heilpraktiker",
          "psychotherapie",
          "psychotherapeut",
          "psychotherapeutin",
          "hebamme",
          "optik",
          "optiker",
          "augenoptik",
          "h\xF6rger\xE4te",
          "h\xF6rakustik",
          "rezeptgeb\xFChr",
          "\xE4rztehaus",
          "zahn\xE4rzte"
        ],
        "out"
      ],
      [
        "sports-fitness",
        [
          "clever fit",
          "cleverfit",
          "finion",
          "mcfit",
          "fitx",
          "urban sports",
          "body & soul",
          "john reed",
          "kieser training",
          "egym",
          "wellpass",
          "hansefit",
          "eversports",
          "boulderwelt",
          "freeletics",
          "gymondo",
          "peloton",
          "zwift"
        ],
        "both"
      ],
      [
        "sports-fitness",
        [
          "fitnessstudio",
          "kletterhalle",
          "boulder",
          "fitness",
          "gym",
          "yoga",
          "pilates",
          "boulderhalle",
          "kletterzentrum",
          "kletterwald",
          "schwimmbad",
          "hallenbad",
          "freibad",
          "b\xE4derbetriebe",
          "stadtbad",
          "eishalle",
          "eisstadion",
          "skihalle",
          "tennis",
          "sporthalle",
          "sportplatz",
          "schulsportplatz",
          "tennisclub"
        ],
        "out"
      ],
      [
        "personal-care",
        [
          "parf\xFCmerie douglas",
          "douglas parf\xFCmerie"
        ],
        "both"
      ],
      [
        "personal-care",
        [
          "friseur",
          "hairstyling",
          "barber",
          "kosmetik",
          "nagelstudio",
          "fris\xF6r",
          "friseursalon",
          "fris\xF6rsalon",
          "haarstudio",
          "barbershop",
          "barbier",
          "nails",
          "naildesign",
          "kosmetikstudio",
          "kosmetikinstitut",
          "beautysalon",
          "beauty",
          "waxing",
          "massage",
          "massagen",
          "sonnenstudio",
          "solarium",
          "wimpern",
          "fu\xDFpflege",
          "tattoo",
          "piercing",
          "friseure",
          "friseurinnen",
          "hair design",
          "hairstyle"
        ],
        "out"
      ],
      [
        "going-out",
        [
          "berghain"
        ],
        "both"
      ],
      [
        "going-out",
        [
          "bar tapas",
          "cocktail",
          "brauhaus",
          "biergarten",
          "kneipe",
          "irish pub",
          "weinbar",
          "sports bar",
          "cocktailbar",
          "pub",
          "nachtclub",
          "diskothek",
          "disco",
          "shisha",
          "bierhalle",
          "bierkeller",
          "weinstube"
        ],
        "out"
      ],
      [
        "clothes",
        [
          "zalando",
          "h&m",
          "h & m",
          "zara deutschland",
          "zara.com",
          "zara store",
          "c&a",
          "primark",
          "tk maxx",
          "tkmaxx",
          "snipes",
          "about you",
          "aboutyou",
          "jack wolfskin",
          "humana",
          "bonprix",
          "shein",
          "asos",
          "mytheresa",
          "engelhorn",
          "takko",
          "nkd",
          "adler mode",
          "adler modem\xE4rkte",
          "caf\xE9 coton",
          "hennes & mauritz",
          "puma store",
          "mango store",
          "only store",
          "globetrotter ausr\xFCstung",
          "levi strauss",
          "levi's store",
          "m&s outlet",
          "marks & spencer outlet"
        ],
        "both"
      ],
      [
        "clothes",
        [
          "momox fashion"
        ],
        "out"
      ],
      [
        "clothes",
        [
          "vinted",
          "kleiderkreisel"
        ],
        "out"
      ],
      [
        "clothes",
        [
          "schuhe",
          "schuhhaus",
          "schuhcenter",
          "modehaus",
          "boutique",
          "fashion",
          "jeans",
          "dessous",
          "lingerie",
          "trachten",
          "strumpfmoden",
          "schmuck",
          "uhren"
        ],
        "out"
      ],
      [
        "shopping",
        [
          "tedi",
          "woolworth",
          "kik fil",
          "flying tiger",
          "nanu-nana",
          "nanu nana",
          "euroshop",
          "tiger store",
          "kaufland e-commerce",
          "kaufland.de",
          "action deutschland",
          "pepco"
        ],
        "both"
      ],
      [
        "shopping",
        [
          "kaufhaus",
          "sonderposten",
          "duty free"
        ],
        "out"
      ],
      [
        "gifts",
        [
          "fleurop",
          "wunschgutschein",
          "jochen schweizer",
          "mydays",
          "smartbox"
        ],
        "both"
      ],
      [
        "gifts",
        [
          "floristik",
          "florist",
          "blumenladen",
          "blumen",
          "blumenhaus",
          "geschenke",
          "geschenkeladen",
          "geschenkshop"
        ],
        "out"
      ],
      [
        "electronics",
        [
          "apple store",
          "mediamarkt",
          "media markt",
          "mediamarktsaturn",
          "saturn",
          "cyberport",
          "notebooksbilliger",
          "conrad electronic",
          "gravis",
          "alternate",
          "mindfactory",
          "caseking",
          "computeruniverse",
          "proshop",
          "reichelt elektronik",
          "pollin electronic",
          "berrybase",
          "backmarket",
          "back market",
          "refurbed",
          "dell",
          "lenovo",
          "logitech",
          "anker innovations",
          "sonos",
          "lautsprecher teufel",
          "nubert",
          "expert technomarkt"
        ],
        "both"
      ],
      [
        "electronics",
        [
          "elektromarkt",
          "computer"
        ],
        "out"
      ],
      [
        "education",
        [
          "goethe-institut",
          "inlingua",
          "coursera",
          "udemy",
          "linkedin learning",
          "toefl",
          "ielts"
        ],
        "both"
      ],
      [
        "education",
        [
          "fahrschule",
          "semesterbeitrag",
          "technische universit\xE4t",
          "hochschule",
          "sprachschule",
          "universit\xE4t",
          "university",
          "semestergeb\xFChr",
          "semesterbeitr\xE4ge",
          "studiengeb\xFChr",
          "studiengeb\xFChren",
          "r\xFCckmeldegeb\xFChr",
          "studienbeitrag",
          "verwaltungskostenbeitrag",
          "immatrikulation",
          "volkshochschule",
          "vhs",
          "fernuniversit\xE4t",
          "fernuni",
          "fernstudium",
          "schulgeld",
          "pr\xFCfungsgeb\xFChr",
          "pr\xFCfungsgeb\xFChren",
          "f\xFChrerschein",
          "fahrstunde",
          "fahrstunden",
          "kursgeb\xFChr",
          "bibliothek",
          "stadtbibliothek",
          "b\xFCcherei"
        ],
        "out"
      ],
      [
        "memberships",
        [
          "adac",
          "adfc",
          "alpenverein",
          "dav sektion",
          "dlrg",
          "ver.di",
          "dgb",
          "haus & grund"
        ],
        "both"
      ],
      [
        "memberships",
        [
          "mitgliedsbeitrag",
          "gewerkschaft",
          "mitgliedsbeitr\xE4ge",
          "mitgliedschaft",
          "vereinsbeitrag",
          "mieterverein",
          "sportverein",
          "turnverein",
          "f\xF6rderverein",
          "vereinsbeitr\xE4ge",
          "vereinsmitgliedschaft",
          "mitgliedsgeb\xFChr",
          "mitgliedsgeb\xFChren",
          "parteibeitrag",
          "parteibeitr\xE4ge",
          "gewerkschaftsbeitrag",
          "gewerkschaftsbeitr\xE4ge",
          "clubbeitrag",
          "clubbeitr\xE4ge",
          "klubbeitrag",
          "klubbeitr\xE4ge"
        ],
        "out"
      ],
      [
        "donations",
        [
          "greenpeace",
          "amnesty",
          "unicef",
          "wwf",
          "\xE4rzte ohne grenzen",
          "m\xE9decins sans fronti\xE8res",
          "brot f\xFCr die welt",
          "misereor",
          "sos-kinderdorf",
          "welthungerhilfe",
          "save the children",
          "plan international",
          "nabu",
          "bund naturschutz",
          "foodwatch",
          "campact",
          "betterplace",
          "wikimedia",
          "sea-watch",
          "mission lifeline",
          "aktion deutschland hilft",
          "deutsche krebshilfe",
          "kindernothilfe",
          "care deutschland",
          "oxfam",
          "terre des hommes"
        ],
        "both"
      ],
      [
        "donations",
        [
          "gofundme"
        ],
        "out"
      ],
      [
        "donations",
        [
          "spende",
          "spenden",
          "kollekte"
        ],
        "out"
      ],
      [
        "eating-out",
        [
          "studierendenwerk",
          "studentenwerk"
        ],
        "out"
      ]
    ],
    merchants: [
      [
        "groceries",
        [
          "penny",
          "norma",
          "netto",
          "spar",
          "real",
          "hit",
          "globus",
          "konsum",
          "picnic"
        ],
        "both"
      ],
      [
        "groceries",
        [
          "flink"
        ],
        "out"
      ],
      [
        "eating-out",
        [
          "nordsee"
        ],
        "both"
      ],
      [
        "coffee-snacks",
        [
          "bahlsen",
          "eilles",
          "lindt",
          "l\xE4derach",
          "neuhaus",
          "storck"
        ],
        "both"
      ],
      [
        "utilities",
        [
          "ewv",
          "eam",
          "ewr",
          "evo",
          "avu",
          "eswe",
          "ggew",
          "ovag",
          "teag",
          "swb"
        ],
        "both"
      ],
      [
        "household",
        [
          "bauhaus",
          "hellweg",
          "roller",
          "porta",
          "depot",
          "poco"
        ],
        "both"
      ],
      [
        "car-fuel",
        [
          "jet",
          "total",
          "star",
          "westfalen",
          "tesla"
        ],
        "both"
      ],
      [
        "car-fuel",
        [
          "abarth",
          "acura",
          "aixam",
          "alfa romeo",
          "aston martin",
          "audi",
          "bentley",
          "bmw",
          "byd",
          "cadillac",
          "chevrolet",
          "chrysler",
          "citro\xEBn",
          "cupra",
          "dacia",
          "daihatsu",
          "dodge",
          "ferrari",
          "fiat",
          "ford",
          "honda",
          "hyundai",
          "infiniti",
          "isuzu",
          "jeep",
          "kia",
          "koenigsegg",
          "lamborghini",
          "lancia",
          "land rover",
          "maserati",
          "mazda",
          "mclaren",
          "mercedes-benz",
          "mitsubishi",
          "nissan",
          "opel",
          "peugeot",
          "polestar",
          "porsche",
          "range rover",
          "renault",
          "rolls-royce",
          "skoda",
          "ssangyong",
          "subaru",
          "suzuki",
          "toyota",
          "vauxhall",
          "volkswagen",
          "volvo",
          "xpeng",
          "bp",
          "q1",
          "oil!"
        ],
        "out"
      ],
      [
        "taxi-sharing",
        [
          "uber"
        ],
        "out"
      ],
      [
        "taxi-sharing",
        [
          "cambio"
        ],
        "both"
      ],
      [
        "travel",
        [
          "hertz",
          "budget",
          "enterprise",
          "alamo",
          "thrifty",
          "adina",
          "aloft",
          "campanile",
          "avis"
        ],
        "both"
      ],
      [
        "personal-care",
        [
          "lush",
          "kiko",
          "douglas"
        ],
        "both"
      ],
      [
        "hobbies",
        [
          "thalia",
          "thomann"
        ],
        "both"
      ],
      [
        "subscriptions",
        [
          "sky"
        ],
        "both"
      ],
      [
        "clothes",
        [
          "zara",
          "globetrotter",
          "mango",
          "only",
          "next",
          "guess",
          "vans",
          "reserved",
          "converse",
          "columbia",
          "champion",
          "gabor",
          "palmers",
          "bonita",
          "cecil",
          "salamander",
          "zero",
          "closed",
          "stradivarius",
          "ecco",
          "barbour",
          "o'neill",
          "mephisto",
          "parfois",
          "reno",
          "outfit",
          "street shoes",
          "r.m.williams",
          "red wing",
          "we fashion",
          "herm\xE8s",
          "bvlgari",
          "bulgari"
        ],
        "both"
      ],
      [
        "electronics",
        [
          "expert",
          "teufel"
        ],
        "both"
      ],
      [
        "shopping",
        [
          "action"
        ],
        "both"
      ],
      [
        "insurance",
        [
          "ergo",
          "n\xFCrnberger",
          "w\xFCrttembergische",
          "mecklenburgische",
          "die bayerische",
          "gothaer",
          "hallesche"
        ],
        "both"
      ],
      [
        "memberships",
        [
          "spd",
          "cdu",
          "csu",
          "fdp",
          "afd",
          "b\xFCndnis 90 die gr\xFCnen",
          "die linke",
          "sozialdemokratische partei deutschlands",
          "christlich demokratische union",
          "christlich demokratische union deutschlands",
          "christlich soziale union",
          "christlich soziale union in bayern",
          "freie demokratische partei",
          "alternative f\xFCr deutschland",
          "gew",
          "ngg",
          "gdp",
          "evg"
        ],
        "out"
      ],
      [
        "memberships",
        [
          "verdi"
        ],
        "both"
      ]
    ],
    noBranches: [
      "cambio",
      "uber",
      "flink",
      "picnic"
    ],
    brands: [
      [
        "groceries",
        [
          "7-eleven",
          "7-eleven australia",
          "7-eleven canada",
          "7-eleven philippines",
          "alldrink",
          "ampm",
          "barrique",
          "bilgro",
          "caltex",
          "cap-markt",
          "carrefour",
          "carrefour express",
          "carrefour market",
          "circle k canada",
          "deutsche see",
          "dia market",
          "diska",
          "dornseifer",
          "dornseifers frischemarkt",
          "dursty",
          "e neukauf",
          "eataly",
          "ebl-naturkost",
          "elli-markt",
          "eni shop",
          "exxon",
          "exxon tiger mart",
          "fakta",
          "feneberg",
          "fristo",
          "georg jos kaes",
          "getr\xE4nke arena",
          "getr\xE4nke city",
          "getr\xE4nke hoffmann",
          "getr\xE4nke quelle",
          "getr\xE4nkeland",
          "getr\xE4nkewelt",
          "go asia",
          "gutkauf",
          "herkules ecenter",
          "hit ullrich",
          "hol'ab",
          "intermarch\xE9",
          "jacques' wein-depot",
          "k kiosk",
          "k+k",
          "kusmi tea",
          "logo getr\xE4nke-fachmarkt",
          "lukoil minimarket",
          "lukoil shop",
          "lukoil trgovina",
          "m&s simply food",
          "mac's convenience stores",
          "markgrafen getr\xE4nkevertrieb",
          "markgrafen getr\xE4nkevertrieb gmbh",
          "marks & spencer simply food",
          "mini mix",
          "mini mix markt",
          "mix markt",
          "mobil mart",
          "nah & frisch",
          "nah & gut",
          "nah und frisch",
          "nah und gut",
          "netto getr\xE4nke-discount",
          "netto polska",
          "np-markt",
          "oil & vinegar",
          "petit casino",
          "reformhaus bacher",
          "reformhaus engelhardt",
          "richter erzgebirge",
          "rindchen's weinkontor",
          "sagasser",
          "scheck-in center",
          "seven eleven",
          "sobi",
          "sonnentor",
          "star mart",
          "superbiomarkt",
          "tante enso",
          "teegschwendner",
          "tesco",
          "tesco express",
          "tesco metro",
          "tesco superstore",
          "tiger mart",
          "toot'n totum",
          "trink & spare",
          "trinkgut",
          "twg tea",
          "v-markt",
          "vinzenzmurr",
          "vitalia",
          "vitalia reformhaus",
          "vomfass",
          "wajos",
          "wasgau",
          "yorma's"
        ]
      ],
      [
        "drugstore",
        [
          "watsons"
        ]
      ],
      [
        "eating-out",
        [
          "60 seconds to napoli",
          "aposto",
          "applebee's",
          "asiahung",
          "auntie anne's",
          "auntie annes pretzels",
          "bageterie boulevard",
          "beets & roots",
          "belchicken",
          "bigchefs",
          "brezelk\xF6nig",
          "burgerheart",
          "burgerme",
          "burguer king",
          "carl's jr.",
          "checkers drive-in restaurants, inc",
          "chipotle",
          "dairy queen",
          "domino's",
          "domino's australia",
          "doughnut time",
          "dunkin doughnuts",
          "dunkin'",
          "es teler 77",
          "fireaway",
          "fogo de ch\xE3o",
          "freddy fresh",
          "frittenwerk",
          "fruitisimo",
          "gosch sylt",
          "haidilao hot pot",
          "hardee's",
          "haus des d\xF6ners",
          "hesburger",
          "hooters",
          "ihop",
          "international house of pancakes",
          "johnny rockets",
          "jollibee",
          "kbtr",
          "kochl\xF6ffel",
          "krispy kreme",
          "krispy kreme doughnuts",
          "la donuteria",
          "little caesars",
          "little ceasars",
          "long john silver's",
          "loving hut",
          "ma'loa",
          "maredo",
          "marrybrown",
          "mealtime malatang",
          "mission bbq",
          "mister donut",
          "mr. sub",
          "nobu",
          "o'tacos",
          "old chang kee",
          "olive garden",
          "olive garden italian kitchen",
          "panda express",
          "papa john",
          "papa john's",
          "papparich",
          "pelicana",
          "pepper lunch",
          "peter pane",
          "pita pit",
          "pollo campero",
          "pollo tropical",
          "pommesfreunde",
          "popeyes",
          "potato corner",
          "pret a manger",
          "quiznos",
          "quiznos sub",
          "quiznos subs",
          "red lobster",
          "royal donuts",
          "ruby tuesday",
          "saizeriya",
          "saravana bhavan",
          "saravanaa bhavan",
          "sausalitos",
          "sbarro",
          "schweinske",
          "shake shack",
          "shakey's",
          "shoo loong kan",
          "sticks'n'sushi",
          "swing kitchen",
          "taco bell",
          "telepizza",
          "tgi fridays",
          "tony roma",
          "tony roma's",
          "wagamama",
          "wahlburgers",
          "wayback burgers",
          "wilma wunder",
          "wimpy restaurants",
          "xiaolongkan",
          "\xE7i\u011Fk\xF6ftem"
        ]
      ],
      [
        "coffee-snacks",
        [
          "allw\xF6rden",
          "amorino",
          "arko",
          "bahlsen outlet",
          "barbarossa brotkultur",
          "baskin-robbins",
          "bears & friends",
          "ben & jerry's",
          "ben's cookies",
          "brioche dor\xE9e",
          "brothaus",
          "b\xE4ren-treff",
          "b\xE4renland",
          "cadera",
          "campus suite",
          "chatime",
          "cinnabon",
          "coco fresh tea & juice",
          "coffeeshop company",
          "cold stone",
          "cold stone creamery",
          "costa drive through",
          "costa drive thru",
          "dallmeyers backhus",
          "dat backhus",
          "debeukelaer",
          "debeukelaer factory outlet",
          "die lohner's",
          "ding tea",
          "d\xE9lifrance",
          "d\xF6bbe",
          "el&n london",
          "erster wiener",
          "espressolab",
          "familienb\xE4cker musswessels",
          "gilgen's",
          "goeken backen",
          "grimminger",
          "g\xF6ing",
          "haferkater",
          "happy lemon",
          "heberer",
          "helbing mein lieblingsb\xE4cker",
          "hinnerb\xE4cker",
          "hofpfisterei",
          "hosselmann",
          "hussel",
          "h\xE4agen-dazs",
          "ihle",
          "ihr landb\xE4cker",
          "janny's",
          "janny's eis",
          "jeff de bruges",
          "joe & the juice",
          "julius meinl",
          "kf tea",
          "kolls",
          "kung fu tea",
          "la romana",
          "lavazza",
          "le chocolat alain ducasse",
          "le pain quotidien",
          "leifert",
          "lieblingsb\xE4cker",
          "lohner's",
          "luckin",
          "l\xF6wenb\xE4cker schaper",
          "machi machi",
          "malzers",
          "marble slab creamery",
          "mein lieblingsb\xE4cker",
          "milkau",
          "millie's cookies",
          "musswessels",
          "m\xFCller & egerer",
          "m\xFCller egerer",
          "m\xFCller und egerer",
          "nahrstedt",
          "nuttea",
          "oebel",
          "onezo",
          "onezo tapioca",
          "onezo tea",
          "pappert",
          "papperts",
          "pekara",
          "pinkberry",
          "rischart",
          "rose bakeshop",
          "royaltea",
          "schw\xE4lmer brotladen",
          "second cup",
          "segafredo",
          "sipl",
          "steinecke",
          "steiskal",
          "sternenb\xE4ck",
          "stinges",
          "storck welt outlet",
          "tcby",
          "teeamo",
          "tiger sugar",
          "tim hortons",
          "uncle tetsu's cheesecake",
          "viba",
          "von allw\xF6rden",
          "wiener feinb\xE4cker",
          "wiener feinb\xE4cker heberer",
          "wonderwaffel",
          "xing fu tang",
          "yi fang fruit tea",
          "yi fang taiwan fruit tea",
          "yi fang tea",
          "yogen fr\xFCz",
          "yogorino",
          "zeit f\xFCr brot"
        ]
      ],
      [
        "household",
        [
          "ace hardware",
          "asian paints",
          "bauking",
          "bauspezi",
          "boconcept",
          "bolia",
          "brillux",
          "bulthaup",
          "butlers",
          "dehner",
          "dille & kamille",
          "dulux",
          "dulux paints",
          "emma sleep",
          "enza home",
          "espa\xE7o casa",
          "farrow & ball",
          "fissler",
          "hagebau",
          "hagebaumarkt",
          "hardeck",
          "herkules bau&garten",
          "home24",
          "iittala",
          "intratuin",
          "jotun",
          "kibek",
          "kodi",
          "k\xFCchentreff",
          "le creuset",
          "leroy merlin",
          "ligne roset",
          "maisons du monde",
          "meda k\xFCchenfachmarkt",
          "multipolster",
          "musterring",
          "natuzzi",
          "natuzzi italia",
          "plana k\xFCchenland",
          "poggenpohl",
          "poltrona frau",
          "porta k\xFCchenwelt",
          "pottery barn",
          "pottery barn kids",
          "raiffeisen-markt",
          "rhg bau & garten",
          "richter+frenzel",
          "roche bobois",
          "sconto sb",
          "screwfix",
          "seats and sofas",
          "segm\xFCller",
          "sherwin williams paint store",
          "sherwin williams paints",
          "sherwin-williams",
          "siematic",
          "s\xF8strene grene",
          "tedox",
          "tefal",
          "tempur",
          "tescoma",
          "villeroy & boch",
          "west elm",
          "wmf",
          "xenos",
          "yata\u015F",
          "yata\u015F bedding",
          "yves delorme",
          "zg raiffeisen",
          "zg raiffeisen baustoffe",
          "zg raiffeisen markt",
          "zurbr\xFCggen"
        ]
      ],
      [
        "pets",
        [
          "anicura",
          "megazoo"
        ]
      ],
      [
        "bus-train",
        [
          "arriva",
          "augsburger verkehrs- und tarifverbund",
          "barnimer busgesellschaft",
          "batik solo trans",
          "big bus tours",
          "blablabus",
          "braunschweiger verkehrs-gmbh",
          "busverkehr emsland-mitte/nord",
          "bv emsland-mitte/nord",
          "b\xFCrgerbus fredenbeck",
          "b\xFCrgerbus remscheid",
          "cebus",
          "ch-direct",
          "ch-integral",
          "chemins de fer luxembourgeois",
          "die \xF6ffies",
          "die \xF6ffis",
          "dingolfinger regionalbusnetz",
          "dlov",
          "donau-iller-nahverkehrsverbund",
          "eurobahn",
          "eurocity",
          "euronight",
          "european sleeper",
          "filsland mobilit\xE4tsverbund",
          "filsland mobilit\xE4tsverbund gmbh",
          "freiburger verkehrs ag",
          "gemeinschaftstarif mecklenburgische seenplatte",
          "gro\xDFraum-verkehr hannover",
          "h3nv",
          "heidenheimer tarfivverbund",
          "heidenheimer tarifverbund",
          "idbus",
          "inselbus norderney",
          "invg",
          "ivrpv",
          "kalb-linien",
          "keolis",
          "kissingen mobil",
          "koleje dolno\u015Bl\u0105skie",
          "kombus",
          "kooperationsgemeinschaft \u201Evorpommern\u201C",
          "kreisverkehr schw\xE4bisch hall",
          "landkreislinien schwandorf",
          "leo express",
          "luxemburgische eisenbahnen",
          "mad t\u0159eb\xED\u010D",
          "magdeburger regionalverkehrsverbund",
          "marego",
          "meininger busbetrieb",
          "mhd dpmml",
          "mhd jablonec nad nisou",
          "mhd jihlava",
          "mhd liberec",
          "mhd opava",
          "mhd prost\u011Bjov",
          "mhd p\xEDsek",
          "mhd uhersk\xE9 hradi\u0161t\u011B",
          "mhd v pardubic\xEDch",
          "mhd \u010Desk\xE1 l\xEDpa",
          "m\xFCnchner verkehrs- und tarifverbund",
          "nahbus nordwestmecklenburg gmbh",
          "nahverkehrsverbund schleswig-holstein",
          "nationale gesellschaft der luxemburgischen eisenbahnen",
          "ostalbmobil",
          "ouibus",
          "ovg sonneberg",
          "regiojet",
          "regionalverkehr allg\xE4u",
          "regionalverkehr oberbayern",
          "rgtr",
          "rhein-nahe nahverkehrsverbund",
          "rhein-neckar-verkehr",
          "rovg",
          "rvs regionalbusverkehr s\xFCdwest gmbh",
          "soci\xE9t\xE9 nationale des chemins de fer luxembourgeois",
          "stadt-bus-verkehr straubing",
          "stadtverkehr rosenheim",
          "stendalbus",
          "suburbano",
          "swisspass",
          "sylter linienverkehr",
          "s\xFCdwestbus",
          "tarifverbund ortenau",
          "tecl",
          "transporte urbano de linares",
          "tuticket",
          "t\xF3rshavn",
          "vag verkehrs-aktiengesellschaft n\xFCrnberg",
          "verbundtarif donauwald",
          "verbundtarif region braunschweig",
          "verkehrs- und tarifgemeinschaft ostharz",
          "verkehrs- und tarifverbund stuttgart",
          "verkehrs-gemeinschaft landkreis freudenstadt",
          "verkehrsbetriebsgesellschaft passau",
          "verkehrsunternehmen wartburgmobil",
          "verkehrsunternehmens-verbund mainfranken",
          "ver\xADkehrs\xADver\xADbund gro\xDF\xADraum n\xFCrn\xADberg",
          "vg rd-eck",
          "vge-s\xFCd",
          "vwg des \xF6pnv s\xF6mmerda",
          "waldshuter tarifverbund",
          "werrabus",
          "westfalentarif",
          "xe bu\xFDt h\u1EA3i ph\xF2ng",
          "zarz\u0105d transportu metropolitalnego",
          "zvon",
          "\xF6ffies",
          "\xF6ffis"
        ]
      ],
      [
        "car-fuel",
        [
          "1a autoservice",
          "afriquia",
          "alliance tire company",
          "ampup",
          "apollo tyres",
          "auto-teile-unger",
          "autofit",
          "bee charging solutions",
          "beyfin",
          "bft",
          "bike-energy",
          "bp america",
          "bp connect",
          "bp gas station",
          "bridgestone",
          "bridgestone india",
          "campsa",
          "chargeone",
          "chargepoint",
          "circle k",
          "citgo",
          "coles express",
          "e-wald",
          "e-wald gmbh",
          "eemobility",
          "eemobility gmbh",
          "ehrle",
          "engie vianeo",
          "eni",
          "eni station",
          "eni wash",
          "euromaster",
          "eurooil",
          "everfuel",
          "evgateway",
          "fastned",
          "gr\xF8nn kontakt",
          "intermarch\xE9 contact",
          "intermarch\xE9 super",
          "ionity",
          "ionity gmbh",
          "junited autoglas",
          "k\xE4rcher clean park",
          "lukoil",
          "mer germany gmbh",
          "milence",
          "milence charging hub",
          "motrio",
          "neste",
          "neste oil",
          "newmotion",
          "nio power",
          "nio power charger",
          "nio power destination",
          "nio power swap",
          "nordoel",
          "novacharge",
          "novus glass",
          "opconnect",
          "orlen",
          "orlen express",
          "oxxo",
          "oxxo gas",
          "petrol ofisi",
          "petrolimex",
          "petronas",
          "pitstop",
          "pneuhage",
          "pneumobil",
          "ptt station",
          "puma energy",
          "pv automotive",
          "quick reifendiscount",
          "quiktrip",
          "quiktrip corporation",
          "racetrac",
          "repsol",
          "rubis",
          "safeway fuel station",
          "sb tank",
          "superwash",
          "swtch",
          "tamoil",
          "tamoil italia spa.",
          "tankpool24",
          "tesla destination charger",
          "tesla france sarl",
          "tesla wall connector",
          "texaco",
          "texaco service station",
          "texaco with techron",
          "tinq",
          "totalerg",
          "ubitricity",
          "ubitricity gmbh",
          "ultramar",
          "valero",
          "verg\xF6lst",
          "vianor",
          "wintec autoglas",
          "wm fahrzeugteile",
          "zg raiffeisen energie"
        ]
      ],
      [
        "taxi-sharing",
        [
          "cambio autodelen",
          "deer gmbh",
          "donkey republic",
          "metropolradruhr",
          "mvgmeinrad",
          "regiorad stuttgart",
          "scouter",
          "sigo",
          "sigo e-lastenrad sharing",
          "sigo e-lastenrad standort",
          "sprottenflotte",
          "stattauto m\xFCnchen",
          "tink konstanz",
          "twsrad",
          "usedomrad",
          "velocity aachen",
          "youbike"
        ]
      ],
      [
        "travel",
        [
          "a&o",
          "adina hotels",
          "akzent hotels",
          "alila",
          "alltours",
          "alua",
          "alua hotels & resorts",
          "andaz",
          "art'otel",
          "autograph collection",
          "b&b hotels",
          "banyan tree",
          "barcel\xF3 hotels & resorts",
          "bed & breakfast hotels",
          "belmond",
          "best western",
          "best western hotels & resorts",
          "best western plus",
          "best western premier",
          "budget car rental",
          "bw premier collection",
          "bw signature collection",
          "catalonia hotels & resorts",
          "centro hotels",
          "clayton hotels",
          "club med",
          "club wyndham",
          "comfort suites",
          "courtyard marriott",
          "crowne plaza",
          "curio collection",
          "curio collection by hilton",
          "days inn",
          "delta hotels",
          "dertour",
          "design hotels",
          "destination by hyatt",
          "deutsches jugendherbergswerk",
          "diamond resorts",
          "dollar car rental",
          "dollar rent a car",
          "dorint",
          "doubletree",
          "easyhotel",
          "enterprise car rental",
          "eurostars",
          "eurostars hotels",
          "executive residency",
          "fairmont",
          "flair hotels",
          "flair hotels ev",
          "flight centre",
          "four points by sheraton",
          "four points flex by sheraton",
          "four seasons",
          "garner hotels",
          "golden tulip",
          "grand hyatt",
          "green motion car rental",
          "gut-gebucht",
          "h-hotels",
          "h10 hotels",
          "hertz car rental",
          "hertz rent a car",
          "hilton",
          "hilton garden inn",
          "hilton grand vacations",
          "hilton hotels & resorts",
          "holiday inn",
          "holiday inn express",
          "holiday inn express & suites",
          "hoteles meininger",
          "howard johnson",
          "hyatt",
          "hyatt centric",
          "hyatt house",
          "hyatt place",
          "hyatt regency",
          "ibis",
          "ibis budget",
          "ibis styles",
          "innside by meli\xE1",
          "intercityhotel",
          "intercontinental",
          "intercontinental hotels & resorts",
          "jdv by hyatt",
          "jo&joe",
          "jufa hotels",
          "jurys",
          "jurys inn",
          "jw marriott",
          "jw marriott hotels",
          "kempinski",
          "kimpton",
          "kuoni",
          "langham hotels & resorts",
          "le m\xE9ridien",
          "leonardo hotels",
          "localiza",
          "logis hotels",
          "ltur",
          "marriott",
          "marriott autograph collection",
          "marriott vacation club",
          "me by meli\xE1",
          "me melia",
          "meli\xE1",
          "meli\xE1 hotels & resorts",
          "mercure",
          "mercure hotels",
          "mgallery",
          "motel one",
          "moxy",
          "nh collection hotels",
          "nh hotels",
          "nhow",
          "novotel",
          "opel rent",
          "oyo",
          "oyo hotels",
          "oyo rooms",
          "pan pacific",
          "park hyatt",
          "park inn",
          "park inn by radisson",
          "park plaza hotels",
          "parkroyal",
          "premier inn",
          "premi\xE8re classe",
          "pullman",
          "radisson",
          "radisson blu",
          "radisson collection",
          "radisson hotels",
          "radisson hotels americas",
          "radisson red",
          "ramada",
          "reiseland",
          "relais & ch\xE2teaux",
          "renaissance hotels",
          "residence inn",
          "ringhotels",
          "ritz carlton",
          "riu",
          "romantik hotels",
          "romantik hotels & restaurants",
          "scandic",
          "scandic hotels",
          "sheraton",
          "six senses",
          "sofitel",
          "spark by hilton",
          "st christopher's inn",
          "st. regis",
          "sta travel",
          "starcar",
          "staycity",
          "staycity aparthotel",
          "staycity aparthotels",
          "super 8 by wyndham",
          "swiss-belhotel",
          "swiss-belinn",
          "swiss\xF4tel",
          "the hoxton",
          "the niu",
          "the ritz",
          "the ritz-carlton",
          "the unbound collection by hyatt",
          "the westin",
          "thrifty car rental",
          "toyoko inn",
          "trademark by wyndham",
          "trademark collection",
          "trademark wyndham",
          "tribute portfolio",
          "tryp",
          "tui",
          "tui reisecenter",
          "unbound collection",
          "unbound hyatt",
          "van der valk",
          "vienna house",
          "voco",
          "w hotels",
          "waldorf astoria",
          "waldorf astoria hotels & resorts",
          "westin",
          "westin hotels & resorts",
          "worldhotel",
          "worldhotels",
          "wyndham",
          "wyndham garden",
          "wyndham grand",
          "zleep hotels"
        ]
      ],
      [
        "health",
        [
          "ace & tate",
          "aktivoptik",
          "alphega pharmacy",
          "amplifon",
          "amplifon deutschland gmbh",
          "amplifon france",
          "audika",
          "becker + fl\xF6ge",
          "dentix",
          "distri club medical",
          "easyapotheke",
          "eyes + more",
          "eyes&more",
          "fielmann",
          "geers",
          "imd berlin",
          "meindentist",
          "mister spex",
          "neuroth",
          "opticalia",
          "specsavers",
          "specsavers opticians",
          "synlab",
          "unilabs",
          "vision express",
          "vitakustik"
        ]
      ],
      [
        "sports-fitness",
        [
          "9round",
          "a3 sport",
          "beat81",
          "bodystreet",
          "crossfit",
          "decathlon",
          "easyfitness",
          "equiva",
          "fitbox",
          "fitinn",
          "fitseveneleven",
          "fitshop",
          "hapik",
          "hervis",
          "hervis sport",
          "hervis sports",
          "hoka",
          "holmes place",
          "ifly",
          "injoy",
          "intersport",
          "kr\xE4mer pferdesport",
          "k\xF6rperformen",
          "mrs. sporty",
          "skiset",
          "sport 2000",
          "sport-tiedje",
          "sports direct",
          "sportscheck",
          "sportsdirect dot com",
          "sportsdirect.com",
          "stadium sports store",
          "the hapik group",
          "topgolf",
          "wellyou"
        ]
      ],
      [
        "personal-care",
        [
          "aesop",
          "avon",
          "bath & body works",
          "bobbi brown",
          "diptyque'",
          "equivalenza",
          "esanelle",
          "essanelle",
          "faberlic",
          "guinot",
          "hair express",
          "hairkiller",
          "house of hair",
          "inglot",
          "itstyle",
          "jo malone",
          "jurlique",
          "kiehl's",
          "kiehl's since 1851",
          "kiko milano",
          "klier",
          "l'occitane",
          "l'occitane en provence",
          "mac cosmetics",
          "malin+goetz",
          "morphe",
          "nature republic",
          "no+vello",
          "oldboy",
          "oriflame",
          "parf\xFCmerie becker",
          "parf\xFCmerie pieper",
          "pupa milano",
          "qb house",
          "rituals",
          "rituals cosmetics",
          "sabon",
          "saint algue",
          "sassoon salon",
          "schuback",
          "schuback parf\xFCmerien",
          "sephora",
          "shiseido",
          "stadtparf\xFCmerie pieper",
          "stylebox",
          "stylebox klier",
          "styleboxx",
          "styleboxx klier",
          "sunpoint",
          "super cut",
          "the body shop",
          "toni & guy",
          "top hair",
          "ziaja"
        ]
      ],
      [
        "going-out",
        [
          "belushi's",
          "brewdog",
          "coyote ugly",
          "coyote ugly saloon"
        ]
      ],
      [
        "entertainment",
        [
          "cinemark",
          "cinemotion",
          "cineplex",
          "cin\xE9polis",
          "fox in a box",
          "legoland",
          "legoland discovery centre",
          "uci kinowelt"
        ]
      ],
      [
        "hobbies",
        [
          "boesner",
          "b\xFCcher pustet",
          "fahrrad xxl",
          "games workshop",
          "hugendubel",
          "little john bikes",
          "lumas",
          "mayersche",
          "osiander",
          "readshop",
          "tokyobike",
          "trek bicycle",
          "tsutaya",
          "warhammer",
          "whsmith",
          "wolle r\xF6del",
          "yellowkorner",
          "zweirad-center stadler"
        ]
      ],
      [
        "clothes",
        [
          "& other stories",
          "5.11 tactical",
          "585 gold",
          "a. lange & s\xF6hne",
          "abc schuh-center",
          "abercrombie & fitch",
          "abercrombie kids",
          "adidas",
          "adidas original",
          "adidas originals",
          "aeropostale",
          "agent provocateur",
          "aldo shoes",
          "alexander mcqueen",
          "allbirds",
          "amo's style",
          "anson's",
          "apm monaco",
          "ara shoes",
          "aristocrazy",
          "arket",
          "armani exchange",
          "asics",
          "athletes world",
          "aubade",
          "audemars piguet",
          "awg-modecenter",
          "ba&sh",
          "balenciaga",
          "baleno",
          "bally",
          "banana republic",
          "banana republic factory",
          "bata",
          "baume & mercier",
          "ben sherman",
          "bershka",
          "betty barclay",
          "bijou brigitte",
          "billabong",
          "bimba & lola",
          "bimba y lola",
          "birkenstock",
          "bleufor\xEAt",
          "blue tomato",
          "body glove",
          "boggi milano",
          "bogner",
          "bonita men",
          "bottega veneta",
          "brandy melville",
          "brax",
          "breitling",
          "breuninger",
          "brooks brothers",
          "brunello cucinelli",
          "bruno banani",
          "bugatti",
          "burberry",
          "calida",
          "calvin klein",
          "calzedonia",
          "camel active",
          "camp david",
          "canada goose",
          "canali",
          "carhartt work in progress",
          "carters babies and kids",
          "catimini",
          "celio",
          "charles v\xF6gele",
          "chaumet",
          "claire's stores",
          "claires accessories",
          "claudie pierlot",
          "coach new york",
          "coach ny",
          "coccinelle",
          "coccodrillo",
          "cole haan",
          "cosmoparis",
          "cotton on body",
          "cotton on kids",
          "cot\xE9lac",
          "crocs",
          "defacto",
          "deichmann",
          "desigual",
          "dkny",
          "doc marten",
          "doc martens",
          "doctor marten",
          "doctor martens",
          "dolce & gabbana",
          "dolce and gabana",
          "dolce and gabanna",
          "dolce and gabbanna",
          "dolce y gabana",
          "dolce y gabanna",
          "dolce y gabbana",
          "dolce y gabbanna",
          "donna karan",
          "donna karan new york",
          "dr. martens",
          "dress barn",
          "du pareil au m\xEAme",
          "dune london",
          "dunhill",
          "ecco shoes",
          "elena mir\xF2",
          "elisabetta franchi",
          "emilio adani",
          "emporio armani",
          "engbers",
          "ermenegildo zegna",
          "ernsting's family",
          "escada",
          "esotiq",
          "essentiel antwerp",
          "etam",
          "eterna",
          "etro",
          "falconeri",
          "fendi",
          "fila",
          "foot locker",
          "foot locker europe",
          "foot solutions",
          "forever 21",
          "french connection",
          "fusalp",
          "fussl",
          "g-star",
          "g-star raw",
          "gap kids",
          "geox",
          "gerry weber",
          "giorgio armani",
          "givenchy",
          "golden goose",
          "gucci",
          "gudrun sj\xF6d\xE9n",
          "guess accessories",
          "g\xF6rtz",
          "g\xF6rtz 17",
          "hackett london",
          "halfprice",
          "hallhuber",
          "hanesbrands",
          "happy socks",
          "havaianas",
          "helly hansen",
          "herzog & br\xE4uer",
          "hollister",
          "house of hoops",
          "hugo boss",
          "humanic",
          "hunkem\xF6ller",
          "hush puppies",
          "iblues",
          "international watch co",
          "international watch company",
          "intimissimi",
          "intimissimi uomo",
          "intrend",
          "izod",
          "jacadi",
          "jack & jones",
          "jaeger-lecoultre",
          "jd sports",
          "jil sander",
          "jimmy choo",
          "juwelier kraemer",
          "k und k schuh-center",
          "k+k schuh-center",
          "kalyan jewellers",
          "karl lagerfeld",
          "kate spade new york",
          "kate spade ny",
          "kenzo",
          "kiabi",
          "kids foot locker",
          "kooka\xEF",
          "koton",
          "la martina",
          "lacoste",
          "lc waikiki",
          "le coq sportif",
          "le slip fran\xE7ais",
          "lee cooper",
          "leguano",
          "leiser comfort",
          "liebeskind berlin",
          "liu jo",
          "loding",
          "longchamp",
          "loro piana",
          "louis vuitton",
          "luisa spagnoli",
          "lululemon",
          "maison margiela",
          "maje",
          "manfield",
          "marc cain",
          "marc o'polo",
          "marella",
          "marina rinaldi",
          "massimo dutti",
          "mavi",
          "mayer's markenschuhe",
          "mcm",
          "mctrek",
          "merrell",
          "mexx",
          "michael kors",
          "mister*lady",
          "modepark r\xF6ther",
          "momoni",
          "moncler",
          "monki",
          "moser trachtenwelt",
          "mountain warehouse",
          "mulberry",
          "my jewellery",
          "myshoes",
          "naf naf",
          "napapijri",
          "nautica",
          "new balance",
          "new yorker",
          "nike",
          "nike clearance store",
          "nike factory store",
          "nike well collective",
          "north sails",
          "ochnik",
          "oka\xEFdi",
          "old navy",
          "olymp & hades",
          "omoda",
          "only & sons",
          "orovivo",
          "orsay",
          "oshkosh",
          "oshkosh b'gosh",
          "ovs",
          "ovs kids",
          "oysho",
          "payless shoesource",
          "peek & cloppenburg",
          "pennyblack",
          "penti",
          "petit bateau",
          "phase eight",
          "pierre cardin",
          "pimkie",
          "pinko",
          "polo ralph lauren",
          "pom d'api",
          "porsche design",
          "prada",
          "princesse tam.tam",
          "promod",
          "pull & bear",
          "puma outlet",
          "punt roma",
          "quick schuh",
          "quicksilver",
          "quiksilver",
          "rainbow shops",
          "red wing shoes",
          "reebok",
          "regatta great outdoors",
          "rieker",
          "rimowa",
          "riu paris",
          "roberto cavalli",
          "rockport",
          "rolex",
          "s.oliver",
          "saint laurent",
          "salvatore ferragamo",
          "samsoe&samsoe",
          "samsonite",
          "sams\xF8e sams\xF8e",
          "san antonio shoe",
          "sas shoes",
          "schiesser",
          "schuh-mann",
          "schuhkay",
          "schuhpark",
          "scotch & soda",
          "sebago",
          "seidensticker",
          "sergent major",
          "shoe4you",
          "sigikid",
          "sinnleffers",
          "sinsay",
          "sisley",
          "sizeer",
          "skechers",
          "skechers usa",
          "sketchers",
          "sportmax",
          "stefanel",
          "stella mccartney",
          "street one",
          "stuart weitzman",
          "suitsupply",
          "superdry",
          "swarovski",
          "swatch",
          "sweaty betty",
          "s\xE9zane",
          "tag heuer",
          "tally weijl",
          "tamaris",
          "tartine et chocolat",
          "ted baker",
          "terranova",
          "tezenis",
          "the athlete's foot",
          "the kooples",
          "the north face",
          "the walking company",
          "thom browne",
          "tiffany & company",
          "timberland",
          "tissot",
          "tom tailor",
          "tommy hilfiger",
          "tommy hilfiger kids",
          "topman",
          "topshop",
          "tory burch",
          "tredy",
          "trigema",
          "tumi",
          "u s polo",
          "u.s. polo assn.",
          "ugg",
          "ugg / ugg australia",
          "ulla popken",
          "under armor",
          "under armour",
          "under armour youth",
          "uniqlo",
          "united colors of benetton",
          "urban outfitters",
          "vacheron constantin",
          "van heusen",
          "van laack",
          "vaude",
          "vero moda",
          "versace",
          "vertbaudet",
          "victoria's secret",
          "vilebrequin",
          "volcom",
          "wacoal",
          "walbusch",
          "weekend max mara",
          "wellensteyn",
          "wempe",
          "witt weiden",
          "wolford",
          "women's secret",
          "women'secret",
          "w\xF6hrl",
          "yours clothing",
          "zadig & voltaire",
          "zeeman",
          "zegna",
          "zilli",
          "\xE9ric bompard"
        ]
      ],
      [
        "electronics",
        [
          "bang & olufsen",
          "beko",
          "bose",
          "capi electronics",
          "coolblue",
          "devialet",
          "digicel",
          "electronicpartner",
          "euronics",
          "harman kardon",
          "hifi klubben",
          "holzleitner",
          "huawei",
          "inmotion",
          "jbl",
          "k&m elektronik",
          "la curacao",
          "leica",
          "lg electronics",
          "medimax",
          "melectronics",
          "miele",
          "oppo",
          "radioshack",
          "samsung",
          "xiaomi"
        ]
      ],
      [
        "shopping",
        [
          "aktionshaus wreesmann",
          "centershop",
          "dufry",
          "galeria",
          "galeria kaufhof",
          "galeria kaufhof gmbh",
          "galeries lafayette",
          "hema",
          "hema b.v.",
          "karstadt",
          "karstadt kaufhof",
          "karstadt warenhaus",
          "karstadt warenhaus gmbh",
          "kr\xFCmet",
          "manufactum",
          "mcarthurglen",
          "mcarthurglen designer outlet",
          "miniso",
          "muji",
          "m\xE4c-geiz",
          "pfennigpfeiffer",
          "postenb\xF6rse",
          "rusta",
          "westfield",
          "wreesmann",
          "wreesmann sonderpostenmarkt"
        ]
      ],
      [
        "gifts",
        [
          "elbenwald",
          "intertoys",
          "lego",
          "lego store",
          "picwictoys",
          "rofu kinderland",
          "smyths",
          "smyths toys",
          "spiele max",
          "steiff"
        ]
      ],
      [
        "education",
        [
          "berlitz",
          "comcave",
          "comcave.college",
          "sae institute",
          "wall street english"
        ]
      ],
      [
        "insurance",
        [
          "big gesundheit",
          "bundesinnungskrankenkasse",
          "bundesinnungskrankenkasse gesundheit",
          "ergo direktversicherung",
          "gm\xFCnder ersatzkasse",
          "handelskrankenkasse",
          "innungskrankenkasse brandenburg und berlin",
          "innungskrankenkasse nord",
          "mapfre",
          "prudential",
          "ruv",
          "saint-gobain betriebskrankenkasse",
          "vgh"
        ]
      ],
      [
        "taxes",
        [
          "lohi",
          "lohi bw",
          "steuerring"
        ]
      ],
      [
        "memberships",
        [
          "ig bau",
          "ig bce",
          "ig metall"
        ]
      ]
    ],
    plainVowelWords: [
      "kuchen",
      "fahre",
      "going"
    ]
  };

  // src/engine/sorting/shop-identity.ts
  var directionalProviders = /* @__PURE__ */ new Set([
    "momox",
    "uber eats",
    "uber trip",
    "goflink",
    "booking.com",
    "fansale",
    "momox fashion",
    "vinted",
    "gofundme"
  ]);
  var genericSavings = /* @__PURE__ */ new Set([
    "sparplan",
    "tagesgeld",
    "festgeld",
    "sparkonto",
    "sparbuch",
    "wertpapierkauf",
    "wertpapierabrechnung",
    "etf",
    "verm\xF6genswirksame leistungen",
    "bausparkasse",
    "bausparvertrag",
    "bausparen"
  ]);
  var list = shops_de_default;
  var matcher = compileShopList({
    ...list,
    rules: list.rules.filter(([category, names2, direction]) => direction === "both" && category !== "own-transfers" || directionalProviders.has(names2[0])).map(([category, names2, direction]) => [
      category,
      category === "savings-investing" ? names2.filter((name) => !genericSavings.has(name)) : names2,
      direction
    ])
  });
  var aliases = /* @__PURE__ */ new Map([
    ["kleiderkreisel", "vinted"],
    ["apple", "apple"],
    ["apple services", "apple"],
    ["apple com bill", "apple"],
    ["apple store", "apple"],
    ["apple distribution international", "apple"],
    ["apple music", "apple"],
    ["apple tv", "apple"]
  ]);
  var legalSuffix = /(?:^| )(?:ug haftungsbeschraenkt|gmbh (?:und )?co kg|pte ltd|sp z o o|s a r l|s r l|s p a|s l|s a|b v|n v|e v|e k|uab|aps|ltd|limited|sas|sarl|ab|as|oy|inc|llc|corp|plc|pty|ohg|mbh|ug|ggmbh|kgaa|aktiengesellschaft|gmbh|ag|se|kg)$/u;
  function cleaned(key) {
    let text3 = shopWords(key.replace(/['’‘`´]/gu, " ")).filter((word) => word !== "&" && word !== "+").join(" ").replace(/\bsagt danke\b|\bdankt\b/gu, " ").replace(/\s+/gu, " ").trim();
    let previous;
    do {
      previous = text3;
      text3 = text3.replace(legalSuffix, "").trim();
    } while (text3 !== previous);
    return text3;
  }
  function knownShop(key, text3) {
    const alias = aliases.get(text3);
    if (alias) return alias;
    const found = matcher.find({ counterparty: key }) ?? matcher.find({ counterparty: text3 });
    return found ? aliases.get(found.name) ?? found.name : null;
  }
  function longer(a, b) {
    return a.length > b.length || a.length === b.length && a < b ? a : b;
  }
  var node = () => ({ children: /* @__PURE__ */ new Map(), best: "", lastWord: "" });
  function shopIdentities(keys) {
    const forms = /* @__PURE__ */ new Map();
    const known = /* @__PURE__ */ new Map();
    for (const key of new Set(keys)) {
      const text3 = cleaned(key);
      forms.set(key, text3);
      if (!text3) continue;
      const shop = knownShop(key, text3);
      if (shop && (!known.has(text3) || shop < known.get(text3))) known.set(text3, shop);
    }
    const names2 = [...new Set(forms.values())].filter(Boolean).sort();
    const parent = new Map(names2.map((name) => [name, name]));
    const anchors = new Map(known);
    const root = (name) => {
      let current = name;
      while (parent.get(current) !== current) current = parent.get(current);
      while (name !== current) {
        const next = parent.get(name);
        parent.set(name, current);
        name = next;
      }
      return current;
    };
    const join = (a, b) => {
      const left = root(a), right = root(b);
      if (left === right) return;
      const leftShop = anchors.get(left), rightShop = anchors.get(right);
      if (leftShop && rightShop && leftShop !== rightShop) return;
      parent.set(right, left);
      anchors.delete(right);
      if (rightShop) anchors.set(left, rightShop);
    };
    const permutations = /* @__PURE__ */ new Map(), endpoints = /* @__PURE__ */ new Map();
    for (const name of names2) {
      const words2 = name.split(" ");
      if (words2.length < 2 || words2.length > 4 || /\p{N}/u.test(name)) continue;
      for (const [index, signature] of [
        [permutations, [...words2].sort().join(" ")],
        [endpoints, `${words2[0]} ${words2.at(-1)}`]
      ]) {
        const previous = index.get(signature);
        if (previous) join(name, previous);
        else index.set(signature, name);
      }
    }
    const trie = node(), ends = /* @__PURE__ */ new Map();
    for (const name of names2) {
      let current = trie, position = 0;
      const lastSpace = name.lastIndexOf(" ");
      for (const letter of name) {
        let child = current.children.get(letter);
        if (!child) {
          child = node();
          current.children.set(letter, child);
        }
        current = child;
        position += letter.length;
        current.best = longer(current.best, name);
        if (position > lastSpace) current.lastWord = longer(current.lastWord, name);
      }
      ends.set(name, current);
    }
    const representatives = /* @__PURE__ */ new Map(), extensions = /* @__PURE__ */ new Map();
    for (const name of names2) {
      const group = root(name), previous = representatives.get(group);
      if (!previous || name.split(" ").length < previous.split(" ").length || name.split(" ").length === previous.split(" ").length && name < previous) representatives.set(group, name);
      if (anchors.has(group) || name.length < 12) continue;
      const end = ends.get(name);
      const target = longer(end.children.get(" ")?.best ?? "", end.lastWord);
      if (target.length <= name.length || root(target) === group) continue;
      extensions.set(group, longer(extensions.get(group) ?? "", target));
    }
    const identities = /* @__PURE__ */ new Map();
    for (const name of names2) {
      let group = root(name);
      const path = [], positions = /* @__PURE__ */ new Map();
      let identity;
      while (true) {
        const saved = identities.get(group);
        if (saved !== void 0) {
          identity = saved;
          break;
        }
        const repeated = positions.get(group);
        if (repeated !== void 0) {
          identity = path.slice(repeated).map((item) => representatives.get(item)).sort()[0];
          break;
        }
        positions.set(group, path.length);
        path.push(group);
        const representative = representatives.get(group);
        const shop = anchors.get(group);
        if (shop) {
          identity = shop;
          break;
        }
        const target = extensions.get(group);
        if (!target) {
          identity = representative;
          break;
        }
        group = root(target);
      }
      for (const item of path) identities.set(item, identity);
    }
    return keys.map((key) => {
      const text3 = forms.get(key);
      return text3 ? identities.get(root(text3)) : "";
    });
  }

  // src/engine/sorting/payment-purpose.ts
  function paymentPurpose(payment) {
    const words2 = shopWords(withoutShopReferences([payment.counterparty, payment.description, payment.bookingText].filter(Boolean).join(" ")));
    const has2 = (...names2) => names2.some((name) => words2.includes(name));
    const amount2 = payment.amount;
    if (typeof amount2 === "number" && Number.isFinite(amount2) && amount2 < 0) {
      if (has2("kantine", "betriebskantine", "mensa")) return "eating-out";
      const purpose = shopWords(withoutShopReferences(payment.description || payment.bookingText || "")).join(" ");
      if (has2("brot") && has2("einkauf") && !purpose.includes("ihr einkauf bei")) return "groceries";
      if ((has2("wolt") || ` ${words2.join(" ")} `.includes(" uber eats ")) && has2("apotheke")) return "health";
    }
    if (typeof amount2 === "number" && Number.isFinite(amount2) && amount2 > 0 && has2("vinted", "kleiderkreisel", "ebay", "kleinanzeigen", "momox", "wirkaufens", "zoxs", "rebuy") && has2("auszahlung", "verkauf", "verkaufserloes", "verkaufserloese") && !has2("erstattung", "rueckerstattung", "rueckzahlung", "rueckgabe", "rueckabwicklung", "retoure", "refund", "stornierung", "storniert")) {
      return "selling-things";
    }
    return null;
  }
  function associationPurpose(payment) {
    if (!(typeof payment.amount === "number" && Number.isFinite(payment.amount) && payment.amount < 0)) return null;
    const payee = withoutShopReferences(payment.counterparty?.trim() || payment.description || payment.bookingText || "");
    return /\be\s*\.\s*v\.?(?=[^.\p{L}\p{N}]|$)/iu.test(payee) || /(?:^| )eingetragener verein(?: |$)/u.test(shopWords(payee).join(" ")) ? "memberships" : null;
  }
  var nonVenueBarWords = new Set(`cash bezahlt zahlung zahlen bezahlen gezahlt bez einzahlung auszahlung abhebung
  erstattung rueckzahlung rechnung betrag geld nail nails brow brows lash lashes beauty juice saft smoothie salat salad
  sushi snack snacks coffee kaffee espresso protein chocolate schoko schokolade riegel equipment zubehoer technik
  druck pressure consulting beratung association code codes de deu eur`.split(/\s+/u));
  function cardVenuePurpose(payment) {
    if (!(typeof payment.amount === "number" && Number.isFinite(payment.amount) && payment.amount < 0)) return null;
    const raw = sortingPayee(payment).toLowerCase().normalize("NFC").replace(BOOKING_TYPE, "");
    const card = cardMerchant(raw);
    if (!card && !SHOP_PROCESSOR_PREFIX.test(raw)) return null;
    const merchant = (card?.merchant ?? raw).replace(SHOP_PROCESSOR_PREFIX, "");
    const words2 = shopWords(merchantKey({ counterparty: merchant }));
    if (!words2.includes("bar")) return null;
    if (words2.some((word) => nonVenueBarWords.has(word))) return null;
    return words2.some((word) => word !== "bar" && /^\p{L}{3,}$/u.test(word)) ? "going-out" : null;
  }

  // src/engine/sorting/starter-rules.ts
  var matcher2 = compileShopList(shops_de_default);
  var STARTER_RULES = matcher2.rules;
  function starterCategory(payment, categories, towns) {
    const categoryId = paymentPurpose(payment) ?? matcher2.match(payment, towns) ?? cardVenuePurpose(payment) ?? associationPurpose(payment);
    return categoryId !== null && categories.some((c) => c.id === categoryId) ? categoryId : null;
  }
  var findShop = (payment, towns) => matcher2.find(payment, towns);

  // src/engine/dates.ts
  var daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
  function parseDay(value) {
    const match = typeof value === "string" ? /^(\d{4})-(\d{2})-(\d{2})/.exec(value) : null;
    if (!match) return null;
    const [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
    return m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m) ? { y, m, d } : null;
  }
  var dayNumber = (day2) => Date.UTC(day2.y, day2.m - 1, day2.d) / 864e5;

  // src/engine/paypal.ts
  var ENGLISH_FUNDING = /* @__PURE__ */ new Set([
    "bank deposit to pp account",
    "general card deposit",
    "general credit card deposit",
    "bank deposit to paypal account",
    "paypal balance manager funding of paypal account",
    "ach funding for funds recovery from account balance",
    "electronic funds transfer funding",
    "credit card deposit for negative paypal account balance"
  ]);
  var plain = (value) => typeof value === "string" ? value.trim().replace(/\s+/g, " ").toLowerCase() : "";
  function isPaypalBankFunding(t) {
    const hay = (t.description + " " + JSON.stringify(t.raw ?? "")).toLowerCase();
    if (hay.includes("bankgutschrift auf paypal")) return true;
    const values = t.raw && typeof t.raw === "object" ? Object.values(t.raw) : [];
    return [t.description, ...values].some((value) => ENGLISH_FUNDING.has(plain(value)));
  }
  var BANK_WITHDRAWALS = /* @__PURE__ */ new Set([
    "von nutzer eingeleitete abbuchung",
    "user initiated withdrawal",
    "manual withdrawal",
    "general withdrawal bank account"
  ]);
  function isPaypalBankWithdrawal(t) {
    return [t.description, field(t.raw, ["Typ", "Type", "Beschreibung"])].some((value) => BANK_WITHDRAWALS.has(plain(value).replace(/[–—]/gu, "-").replace(/\s*-\s*/gu, " ")));
  }
  var CONVERSION_TYPES = /* @__PURE__ */ new Set(["Allgemeine W\xE4hrungsumrechnung", "General Currency Conversion"]);
  var TYPE_KEYS = ["Typ", "Type"];
  var RELATED_KEYS = ["Zugeh\xF6riger Transaktionscode", "Reference Txn ID"];
  var EUR = "EUR";
  function field(raw, keys) {
    if (!raw || typeof raw !== "object") return void 0;
    for (const key of keys) {
      const value = raw[key];
      if (typeof value === "string" && value.trim()) return value.trim();
    }
    return void 0;
  }
  var isConversion = (row) => CONVERSION_TYPES.has(field(row.raw, TYPE_KEYS) ?? "");
  function conversionPlan(rows) {
    const eurLegByPurchase = /* @__PURE__ */ new Map();
    const conversionsByPurchase = /* @__PURE__ */ new Map();
    for (const row of rows) {
      if (!isConversion(row)) continue;
      const purchase = field(row.raw, RELATED_KEYS);
      if (!purchase) continue;
      conversionsByPurchase.set(purchase, [...conversionsByPurchase.get(purchase) ?? [], row]);
      if (row.currency === EUR) eurLegByPurchase.set(purchase, row);
    }
    const dropped = /* @__PURE__ */ new Set();
    const replaced = /* @__PURE__ */ new Map();
    const unmatched = [];
    for (const row of rows) {
      if (row.currency === EUR || isConversion(row) || !row.externalId) continue;
      const eurLeg = eurLegByPurchase.get(row.externalId);
      if (!eurLeg) {
        unmatched.push(row.externalId);
        continue;
      }
      replaced.set(row, { ...row, amount: eurLeg.amount, currency: EUR });
      for (const conversion of conversionsByPurchase.get(row.externalId) ?? []) dropped.add(conversion);
    }
    return { dropped, replaced, unmatched };
  }
  function paypalConversionRows(rows) {
    return conversionPlan(rows).dropped;
  }
  function foldPaypalConversions(rows) {
    const { dropped, replaced, unmatched } = conversionPlan(rows);
    return {
      rows: rows.filter((row) => !dropped.has(row)).map((row) => replaced.get(row) ?? row),
      unmatched
    };
  }

  // src/engine/sorting/transfers.ts
  var OWN_TRANSFERS = "own-transfers";
  var TRANSFER_DAYS = 3;
  var PAYPAL_NAME = /^paypal(?:$|[\s(*.,])/iu;
  var PAYPAL_IN_TEXT = /(?:^|[^\p{L}\p{N}])paypal\s*(?:\(\s*europe|europe\b|\*)/iu;
  function isPaypalBankLine(payment) {
    if (payment.source === "paypal") return false;
    const who = (payment.counterparty?.trim() || payment.description || payment.bookingText || "").trim();
    if (PAYPAL_NAME.test(who)) return true;
    return [payment.counterparty, payment.description, payment.bookingText].some((text3) => typeof text3 === "string" && PAYPAL_IN_TEXT.test(text3));
  }
  function isPaypalFundingRow(payment) {
    return payment.source === "paypal" && isPaypalBankFunding({ description: payment.description ?? "", raw: payment.raw });
  }
  function isPaypalWithdrawalRow(payment) {
    return payment.source === "paypal" && isPaypalBankWithdrawal({ description: payment.description ?? "", raw: payment.raw });
  }
  var OWN_TRANSFER_WORDS = /(?<![\p{L}\p{N}])(?:umbuchung|(?:eigen|konto)?(?:übertrag|uebertrag)|eigene[ns]?\s+konto|own\s+account)(?![\p{L}\p{N}])/iu;
  function saysOwnTransfer(payment) {
    return [payment.counterparty, payment.description, payment.bookingText].some((text3) => typeof text3 === "string" && OWN_TRANSFER_WORDS.test(text3.normalize("NFC")));
  }
  var ibanKey = (value) => (value ?? "").replace(/\s/g, "").toUpperCase();
  var IBAN_SHAPE = /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/;
  function ownIban(payment) {
    const given = ibanKey(payment.accountIban);
    if (given) return given;
    const account = ibanKey(payment.account);
    return IBAN_SHAPE.test(account) ? account : "";
  }
  var proven = (a, b) => a.other !== "" && a.other === b.iban || b.other !== "" && b.other === a.iban || a.says && b.says;
  function ownTransfers(payments) {
    const result = payments.map(() => null);
    let paypalStart = Infinity, paypalEnd = -Infinity;
    for (const p of payments) {
      const date2 = p.source === "paypal" ? parseDay(p.date) : null;
      if (!date2) continue;
      const day2 = dayNumber(date2);
      paypalStart = Math.min(paypalStart, day2);
      paypalEnd = Math.max(paypalEnd, day2);
    }
    const conversions = paypalConversionRows(payments.filter((p) => !isPaypalBankFunding({ description: p.description ?? "", raw: p.raw })));
    payments.forEach((p, i2) => {
      const date2 = parseDay(p.date);
      const day2 = date2 ? dayNumber(date2) : NaN;
      const covered = day2 >= paypalStart - TRANSFER_DAYS && day2 <= paypalEnd + TRANSFER_DAYS;
      if (isPaypalFundingRow(p) || isPaypalWithdrawalRow(p) || covered && isPaypalBankLine(p)) result[i2] = { rule: "paypal" };
      if (conversions.has(p)) result[i2] = { rule: "paypal-conversion" };
    });
    const groups2 = /* @__PURE__ */ new Map();
    payments.forEach((p, index) => {
      if (result[index]?.rule === "paypal-conversion" || isPaypalWithdrawalRow(p)) return;
      const date2 = parseDay(p.date);
      const amount2 = p.amount;
      if (!p.account || !date2 || typeof amount2 !== "number" || !Number.isFinite(amount2)) return;
      const cents7 = Math.round(Math.abs(amount2) * 100);
      if (cents7 === 0) return;
      const group = groups2.get(cents7) ?? { out: [], in: [] };
      (amount2 < 0 ? group.out : group.in).push({
        index,
        account: p.account,
        day: dayNumber(date2),
        currency: p.currency || null,
        iban: ownIban(p),
        other: ibanKey(p.counterpartyIban),
        says: saysOwnTransfer(p)
      });
      groups2.set(cents7, group);
    });
    const candidates = [];
    for (const { out, in: incoming } of groups2.values()) {
      for (const o of out) {
        for (const i2 of incoming) {
          const distance2 = Math.abs(o.day - i2.day);
          if (distance2 > TRANSFER_DAYS || o.account === i2.account) continue;
          if (o.currency && i2.currency && o.currency !== i2.currency) continue;
          if (!proven(o, i2)) continue;
          candidates.push({ a: Math.min(o.index, i2.index), b: Math.max(o.index, i2.index), distance: distance2 });
        }
      }
    }
    candidates.sort((x2, y) => x2.distance - y.distance || x2.a - y.a || x2.b - y.b);
    const paired = /* @__PURE__ */ new Set();
    for (const { a, b } of candidates) {
      if (paired.has(a) || paired.has(b)) continue;
      paired.add(a).add(b);
      result[a] = { rule: "accounts", pairedWith: b };
      result[b] = { rule: "accounts", pairedWith: a };
    }
    return result;
  }

  // src/engine/sorting/local-places-packed.ts
  var PLACES_MAGIC = 1347179073;
  var PLACES_VERSION = 1;
  var PLACES_HEADER_BYTES = 128;
  var NO_LOCAL_CATEGORY = 65535;
  var fail = (reason) => {
    throw new Error(`Invalid packed local places: ${reason}`);
  };
  var aligned = (size) => Math.ceil(size / 4) * 4;
  function placesChecksum(bytes) {
    let hash = 2166136261;
    for (let i2 = 0; i2 < bytes.length; i2++) hash = Math.imul(hash ^ (i2 >= 88 && i2 < 92 ? 0 : bytes[i2]), 16777619);
    return hash >>> 0;
  }
  function localUtf8(text3) {
    const bytes = [];
    for (const char of text3) {
      let cp = char.codePointAt(0);
      if (cp >= 55296 && cp <= 57343) cp = 65533;
      if (cp < 128) bytes.push(cp);
      else if (cp < 2048) bytes.push(192 | cp >> 6, 128 | cp & 63);
      else if (cp < 65536) bytes.push(224 | cp >> 12, 128 | cp >> 6 & 63, 128 | cp & 63);
      else bytes.push(240 | cp >> 18, 128 | cp >> 12 & 63, 128 | cp >> 6 & 63, 128 | cp & 63);
    }
    return new Uint8Array(bytes);
  }
  function textAt(bytes, offsets, row) {
    let text3 = "";
    for (let i2 = offsets[row]; i2 < offsets[row + 1]; ) {
      const b = bytes[i2++];
      let cp = b;
      if (b >= 192) {
        const need = b < 224 ? 1 : b < 240 ? 2 : 3;
        cp = b & (need === 1 ? 31 : need === 2 ? 15 : 7);
        for (let n = 0; n < need; n++) cp = cp << 6 | bytes[i2++] & 63;
      }
      text3 += String.fromCodePoint(cp);
    }
    return text3;
  }
  function compare3(bytes, start, end, other, from2 = 0, to = other.length) {
    while (start < end && from2 < to) {
      const difference = bytes[start++] - other[from2++];
      if (difference) return difference;
    }
    return end - start - (to - from2);
  }
  function checkStrings(bytes, offsets, sorted) {
    if (offsets[0] !== 0 || offsets[offsets.length - 1] !== bytes.length) fail("string offsets");
    for (let row = 0; row + 1 < offsets.length; row++) {
      const start = offsets[row], end = offsets[row + 1];
      if (end < start || end > bytes.length || sorted && end === start) fail("string range");
      if (sorted && row && compare3(bytes, offsets[row - 1], start, bytes, start, end) >= 0) fail("name ordering");
      for (let i2 = start; i2 < end; ) {
        const b = bytes[i2++];
        if (b < 128) continue;
        const need = b >= 194 && b <= 223 ? 1 : b >= 224 && b <= 239 ? 2 : b >= 240 && b <= 244 ? 3 : 0;
        if (!need || i2 + need > end) fail("UTF-8");
        let cp = b & (need === 1 ? 31 : need === 2 ? 15 : 7);
        for (let n = 0; n < need; n++) {
          const next = bytes[i2++];
          if ((next & 192) !== 128) fail("UTF-8");
          cp = cp << 6 | next & 63;
        }
        if (cp < (need === 1 ? 128 : need === 2 ? 2048 : 65536) || cp > 1114111 || cp >= 55296 && cp <= 57343) fail("UTF-8");
      }
    }
  }
  var PackedLocalPlaces = class {
    constructor(input) {
      __publicField(this, "bytes");
      __publicField(this, "header");
      __publicField(this, "nameOffsets");
      __publicField(this, "names");
      __publicField(this, "nationalCategories");
      __publicField(this, "matchOffsets");
      __publicField(this, "matchTowns");
      __publicField(this, "matchCategories");
      __publicField(this, "townOffsets");
      __publicField(this, "towns");
      __publicField(this, "categoryOffsets");
      __publicField(this, "categories");
      __publicField(this, "metadataOffsets");
      __publicField(this, "metadata");
      this.bytes = ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength) : new Uint8Array(input);
      const bytes = this.bytes, base = bytes.byteOffset, buffer = bytes.buffer;
      if (base % 4) fail("buffer byteOffset must be aligned to 4 bytes");
      if (bytes.length < PLACES_HEADER_BYTES) fail("truncated header");
      if (new Uint8Array(new Uint32Array([16909060]).buffer)[0] !== 4) fail("little-endian host required");
      const h = this.header = new Uint32Array(buffer, base, PLACES_HEADER_BYTES / 4);
      if (h[0] !== PLACES_MAGIC) fail("magic");
      if (h[1] !== PLACES_VERSION) fail(`unsupported version ${h[1]}`);
      if (h[2] !== 16909060 || h[8] !== PLACES_HEADER_BYTES || h[3] !== bytes.length) fail("header or file length");
      if (h[6] >= NO_LOCAL_CATEGORY || Array.from(h.subarray(23)).some(Boolean)) fail("header counts or reserved words");
      if (placesChecksum(bytes) !== h[22]) fail("checksum");
      let next = PLACES_HEADER_BYTES;
      const numeric = (word, count, width) => {
        if (h[word] !== next || next + count * width > bytes.length) fail("section bounds or alignment");
        const start = next;
        next += aligned(count * width);
        for (let i2 = start + count * width; i2 < next; i2++) if (bytes[i2]) fail("section padding");
        return base + start;
      };
      const blob = (word, offsets) => {
        const size = offsets[offsets.length - 1];
        const start = numeric(word, size, 1);
        return new Uint8Array(buffer, start, size);
      };
      this.nameOffsets = new Uint32Array(buffer, numeric(9, h[4] + 1, 4), h[4] + 1);
      this.names = blob(10, this.nameOffsets);
      this.nationalCategories = new Uint16Array(buffer, numeric(11, h[4], 2), h[4]);
      this.matchOffsets = new Uint32Array(buffer, numeric(12, h[4] + 1, 4), h[4] + 1);
      this.matchTowns = new Uint32Array(buffer, numeric(13, h[7], 4), h[7]);
      this.matchCategories = new Uint16Array(buffer, numeric(14, h[7], 2), h[7]);
      this.townOffsets = new Uint32Array(buffer, numeric(15, h[5] + 1, 4), h[5] + 1);
      this.towns = blob(16, this.townOffsets);
      this.categoryOffsets = new Uint32Array(buffer, numeric(17, h[6] + 1, 4), h[6] + 1);
      this.categories = blob(18, this.categoryOffsets);
      this.metadataOffsets = new Uint32Array(buffer, numeric(19, 4, 4), 4);
      this.metadata = blob(20, this.metadataOffsets);
      if (next !== bytes.length || h[21] !== next) fail("end offset");
      checkStrings(this.names, this.nameOffsets, true);
      checkStrings(this.towns, this.townOffsets, false);
      checkStrings(this.categories, this.categoryOffsets, false);
      checkStrings(this.metadata, this.metadataOffsets, false);
      if (this.matchOffsets[0] !== 0 || this.matchOffsets[h[4]] !== h[7]) fail("match offsets");
      for (let row = 0; row < h[4]; row++) {
        const category = this.nationalCategories[row];
        if (category !== NO_LOCAL_CATEGORY && category >= h[6]) fail("national category code");
        const start = this.matchOffsets[row], end = this.matchOffsets[row + 1];
        if (end < start || end > h[7]) fail("match range");
        for (let i2 = start; i2 < end; i2++) {
          if (this.matchTowns[i2] >= h[5] || this.matchCategories[i2] >= h[6]) fail("town/category code");
          if (i2 > start && (this.matchTowns[i2] < this.matchTowns[i2 - 1] || this.matchTowns[i2] === this.matchTowns[i2 - 1] && this.matchCategories[i2] < this.matchCategories[i2 - 1])) fail("town match ordering");
        }
      }
    }
    get version() {
      return 1;
    }
    get dataDate() {
      return textAt(this.metadata, this.metadataOffsets, 0);
    }
    get attribution() {
      return textAt(this.metadata, this.metadataOffsets, 1);
    }
    get source() {
      return textAt(this.metadata, this.metadataOffsets, 2);
    }
    rowFor(name) {
      const query = localUtf8(name);
      let low = 0, high = this.nationalCategories.length;
      while (low < high) {
        const middle = low + high >>> 1;
        if (compare3(this.names, this.nameOffsets[middle], this.nameOffsets[middle + 1], query) < 0) low = middle + 1;
        else high = middle;
      }
      return low < this.nationalCategories.length && compare3(this.names, this.nameOffsets[low], this.nameOffsets[low + 1], query) === 0 ? low : -1;
    }
    town(code) {
      return textAt(this.towns, this.townOffsets, code);
    }
    category(code) {
      return textAt(this.categories, this.categoryOffsets, code);
    }
  };

  // src/engine/sorting/local-places.ts
  var packedIndexes = /* @__PURE__ */ new WeakMap();
  var installed;
  function indexLocalPlaces(data) {
    if (data instanceof PackedLocalPlaces || "rows" in data) return data;
    let index = packedIndexes.get(data);
    if (!index) {
      index = new PackedLocalPlaces(data);
      packedIndexes.set(data, index);
    }
    return index;
  }
  function setLocalPlaces(data) {
    const next = data === null ? void 0 : indexLocalPlaces(data);
    installed = next;
  }
  function resolveLocalPlaces(option) {
    return option === true ? installed : option ? indexLocalPlaces(option) : void 0;
  }
  var localName = (text3) => shopWords(text3).join(" ");
  var ordinary = new Set(`lieblingsstueck lieblingsplatz glueck gluecklich zuhause daheim heimat freiheit liebe leben
  sonne mond stern himmel erde wasser feuer luft zeit raum mitte zentral central royal international express
  mueller muller schmidt schneider fischer weber meyer wagner becker schulz hoffmann schaefer koch richter klein wolf
  danke vielen dank einkauf zahlung rechnung gutschrift lastschrift ueberweisung dauerauftrag kartenzahlung
  gehalt lohn miete unterhalt erstattung rueckzahlung umbuchung auszahlung verkauf privat familie freunde
  terminal filiale beleg karte paypal klarna stripe adyen sumup zettle worldline nexi sparkasse volksbank
  deutschland germany berlin hamburg muenchen koeln leipzig restaurant cafe apotheke baeckerei blumen kosmetik
  optik praxis friseur hotel pension parkplatz supermarkt tankstelle shopping fashion beauty service services
  am markt am bahnhof am park zur post zur sonne zum stern
  an im in auf bei beim der die das dem den des ein eine und oder mit ohne fuer von vom`.split(/\s+/u));
  var phrases = /* @__PURE__ */ new Set(["am markt", "am bahnhof", "am park", "zur post", "zur sonne", "zum stern", "vielen dank"]);
  function safeLocalName(name) {
    const words2 = name.split(" ");
    const letters = name.replace(/[^\p{L}]/gu, "").length;
    return name === localName(name) && letters >= 8 && name.length <= 100 && !phrases.has(name) && !(words2.length === 1 && ordinary.has(name)) && words2.some((word) => word.length >= 3 && !ordinary.has(word)) && !/\b(?:iban|eref|mref|gmbh|inhaber|doktor|dr)\b/u.test(name);
  }
  function rowFor(data, name) {
    let low = 0, high = data.rows.length;
    while (low < high) {
      const middle = low + high >>> 1;
      if (data.rows[middle][0] < name) low = middle + 1;
      else high = middle;
    }
    return data.rows[low]?.[0] === name ? data.rows[low] : void 0;
  }
  function findLocalPlace(payment, input) {
    const data = indexLocalPlaces(input);
    if (data.version !== 1 || !(typeof payment.amount === "number" && Number.isFinite(payment.amount) && payment.amount < 0)) return null;
    const raw = payeeText(payment);
    const card = cardMerchant(raw);
    if (card && !/^deu\b/u.test(raw.slice(card.merchant.length).trim())) return null;
    const clean2 = (text3) => localName(text3.toLowerCase().replace(BOOKING_TYPE, "").replace(SHOP_PROCESSOR_PREFIX, "").split(/\b(?:eref|mref|cred|iban|bic|mandatsreferenz|glaeubiger-id|gläubiger-id)\s*[:+]/iu)[0]);
    const head = clean2(card?.merchant ?? raw);
    const details = clean2(payment.description ?? payment.bookingText ?? "");
    const explicitTown = card ? localName(card.town) : "";
    const found = [];
    const consider = (name, tail) => {
      if (!safeLocalName(name)) return;
      const packed = data instanceof PackedLocalPlaces ? data : void 0;
      const row = packed ? void 0 : rowFor(data, name);
      const index = packed ? packed.rowFor(name) : -1;
      if (packed ? index < 0 : !row) return;
      const located = (text3, town) => {
        const country = / (?:de|deu)$/u.test(text3);
        return townMatches(text3.replace(/ (?:de|deu)$/u, ""), town, country);
      };
      const location = (town) => !tail && townMatches(explicitTown, town, true) || located(tail, town) || !tail && details.startsWith(`${name} `) && located(details.slice(name.length + 1), town);
      const categories = /* @__PURE__ */ new Set();
      if (packed) {
        for (let i2 = packed.matchOffsets[index]; i2 < packed.matchOffsets[index + 1]; i2++) {
          if (location(packed.town(packed.matchTowns[i2]))) categories.add(packed.matchCategories[i2]);
        }
      } else {
        const json = data;
        for (let i2 = 0; i2 < row[2].length; i2 += 2) if (location(json.towns[row[2][i2]])) categories.add(row[2][i2 + 1]);
      }
      if (categories.size > 1) {
        found.push({ categoryId: "", name, town: true });
        return;
      }
      const national = packed ? packed.nationalCategories[index] : row[1];
      const category = categories.size ? [...categories][0] : tail ? -1 : national;
      const categoryId = category < 0 || category === NO_LOCAL_CATEGORY ? void 0 : packed ? packed.category(category) : data.categories[category];
      if (categoryId) found.push({ categoryId, name, town: categories.size === 1 });
    };
    consider(head, "");
    const words2 = head.split(" ");
    for (let cut = 1; cut < words2.length; cut++) consider(words2.slice(0, cut).join(" "), words2.slice(cut).join(" "));
    const specific = found.some((match) => match.town) ? found.filter((match) => match.town) : found;
    return specific.length && new Set(specific.map((match) => match.categoryId)).size === 1 && specific[0].categoryId ? specific[0] : null;
  }

  // src/engine/sorting/sort.ts
  function sortPayments(payments, options) {
    const localPlaces = resolveLocalPlaces(options.localPlaces);
    const allowed = new Set(options.categories.map((c) => c.id));
    const starterCategories = localPlaces ? [...DEFAULT_CATEGORIES, ...BUILT_IN_CATEGORIES, ...options.categories] : options.categories;
    const transfers = ownTransfers(payments);
    const provenTowns = /* @__PURE__ */ new Set();
    for (const payment of payments) for (const text3 of [payment.counterparty, payment.description, payment.bookingText]) {
      const card = text3 ? cardMerchant(text3) : null;
      const words2 = card ? shopWords(card.town) : [];
      if (words2.length === 1) provenTowns.add(words2[0]);
    }
    const towns = [...provenTowns];
    const keys = payments.map(merchantKey);
    const learned = options.learned ?? {};
    const learnedKeys = Object.keys(learned).sort();
    const distinct = [.../* @__PURE__ */ new Set([...keys, ...learnedKeys])];
    const shops = shopIdentities(distinct);
    const identities = new Map(distinct.map((key, index) => [key, shops[index]]));
    const rememberedShops = /* @__PURE__ */ new Map();
    for (const key of learnedKeys) {
      const identity = identities.get(key);
      if (identity && allowed.has(learned[key]) && !rememberedShops.has(identity)) rememberedShops.set(identity, learned[key]);
    }
    return payments.map((payment, index) => {
      if (transfers[index]) return { categoryId: OWN_TRANSFERS, source: "structural" };
      const key = keys[index];
      const remembered = !key ? null : Object.hasOwn(learned, key) ? learned[key] : rememberedShops.get(identities.get(key));
      if (remembered && allowed.has(remembered)) return { categoryId: remembered, source: "learned" };
      const existing = starterCategory(payment, starterCategories, towns);
      const local = existing === null && localPlaces ? findLocalPlace(payment, localPlaces)?.categoryId : null;
      const proposed = existing ?? local ?? null;
      const categoryId = proposed && allowed.has(proposed) ? proposed : null;
      return { categoryId, source: categoryId ? "starter" : null };
    });
  }
  function learn(learned, payment, categoryId) {
    const key = merchantKey(payment);
    return key ? { ...learned, [key]: categoryId } : { ...learned };
  }

  // src/engine/receipts/count.ts
  var DASHBOARD_CURRENCY = "EUR";
  var CASH_LOOKBACK_DAYS = 92;
  var COVERED_PLACE = "Covered by receipts";
  var cents = (n) => Math.round(n * 100);
  var day = (date2) => date2.slice(0, 10);
  var byDay = (a, b) => day(a.date) < day(b.date) ? -1 : day(a.date) > day(b.date) ? 1 : 0;
  function checked2(receipts) {
    for (const r of receipts) {
      if (!parseDay(r?.date)) throw new Error(`Receipt ${r?.id}: the date is not an ISO date (YYYY-MM-DD)`);
      if (typeof r.total !== "number" || !Number.isFinite(r.total)) throw new Error(`Receipt ${r.id}: the total is not a number`);
      if (r.method !== "card" && r.method !== "cash") throw new Error(`Receipt ${r.id}: the method is neither card nor cash`);
      if (r.direction != null && r.direction !== "out" && r.direction !== "in") throw new Error(`Receipt ${r.id}: the direction is neither out nor in`);
      if (r.direction === "in" && r.method !== "cash") throw new Error(`Receipt ${r.id}: money received is cash only`);
      if (r.kind != null && r.kind !== "receipt" && r.kind !== "manual") throw new Error(`Receipt ${r.id}: the kind is neither receipt nor manual`);
      if (r.paidFrom != null && typeof r.paidFrom !== "string") throw new Error(`Receipt ${r.id}: paidFrom is not an id`);
    }
    return receipts.filter((r) => r.total > 0);
  }
  var isCashWithdrawal = (p) => p.amount < 0 && findShop({ counterparty: p.counterparty, description: p.description, amount: p.amount })?.categoryId === "cash";
  function countReceipts(payments, receipts, paymentIds) {
    const rows = [];
    const row = (r, amount2) => ({
      id: r.id,
      externalId: "",
      date: day(r.date),
      amount: amount2,
      currency: DASHBOARD_CURRENCY,
      balance: null,
      description: r.shop ?? "",
      counterparty: r.shop ?? "",
      category: r.category,
      receiptId: r.id
    });
    const received = [];
    const spent = [];
    for (const r of checked2(receipts)) {
      if (r.paymentId != null && paymentIds.has(r.paymentId)) continue;
      if ((r.currency || DASHBOARD_CURRENCY).toUpperCase() !== DASHBOARD_CURRENCY) continue;
      if (r.method === "card") rows.push({ ...row(r, -r.total), provisional: true });
      else if (r.direction === "in") {
        rows.push(row(r, r.total));
        received.push(r);
      } else {
        rows.push(row(r, -r.total));
        spent.push(r);
      }
    }
    const number = (date2) => dayNumber(parseDay(date2));
    const withdrawals = payments.filter(isCashWithdrawal);
    const source = (kind, id, date2, euros2, place, category, payment) => ({ kind, id, date: day(date2), day: number(date2), place, category, amount: cents(euros2), left: cents(euros2), by: [], payment });
    const sources = [
      ...withdrawals.map((p) => source("withdrawal", p.id, p.date, -p.amount, p.counterparty || p.description, p.category, p)),
      ...received.map((r) => source("received", r.id, r.date, r.total, r.shop ?? "", r.category, null))
    ];
    const named = /* @__PURE__ */ new Map();
    for (const s of sources) if (!named.has(s.id)) named.set(s.id, s);
    const latestFirst = [...sources].sort((a, b) => b.day - a.day);
    const outs = [...spent].sort(byDay).map((r) => {
      let need = cents(r.total);
      const on = number(r.date);
      const from2 = [];
      const take = (s) => {
        const amount2 = Math.min(s.left, need);
        s.left -= amount2;
        need -= amount2;
        s.by.push(r.id);
        from2.push(s.id);
      };
      const chosen = r.paidFrom != null ? named.get(r.paidFrom) : void 0;
      if (chosen && chosen.day <= on && chosen.left > 0) take(chosen);
      for (const s of latestFirst) {
        if (need === 0) break;
        if (s.left === 0 || s.day > on || on - s.day > CASH_LOOKBACK_DAYS) continue;
        take(s);
      }
      return {
        kind: r.kind === "manual" ? "manual" : "receipt",
        id: r.id,
        date: day(r.date),
        place: r.shop ?? "",
        category: r.category,
        amount: cents(r.total),
        from: from2
      };
    });
    for (const s of sources) {
      if (s.payment === null || s.left === s.amount) continue;
      rows.push({
        id: `${s.id}:covered`,
        externalId: "",
        date: s.date,
        amount: (s.amount - s.left) / 100,
        currency: DASHBOARD_CURRENCY,
        balance: null,
        description: COVERED_PLACE,
        counterparty: COVERED_PLACE,
        category: s.payment.category,
        tags: [...s.payment.tags ?? []],
        coveredBy: [...s.by]
      });
    }
    return { rows, withdrawals: new Set(withdrawals), sources, outs };
  }
  function withReceiptRows(payments, rows) {
    const extra = [...rows].sort((a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
    const merged = [];
    let next = 0;
    for (const p of payments) {
      while (next < extra.length && extra[next].date < day(p.date)) merged.push(extra[next++]);
      merged.push(p);
    }
    return merged.concat(extra.slice(next));
  }
  function cashView(count, categoryName) {
    const ins = count.sources.map((s) => ({
      id: s.id,
      date: s.date,
      amount: s.amount / 100,
      kind: s.kind,
      place: s.place,
      category: categoryName(s.category),
      paidFrom: null,
      coveredBy: [...s.by],
      left: s.left / 100
    }));
    const outs = count.outs.map((o) => ({
      id: o.id,
      date: o.date,
      amount: -o.amount / 100,
      kind: o.kind,
      place: o.place,
      category: categoryName(o.category),
      paidFrom: [...o.from],
      coveredBy: null,
      left: null
    }));
    const movements = [...ins, ...outs].sort(byDay);
    const tally = /* @__PURE__ */ new Map();
    for (const m of movements) {
      const key = m.date.slice(0, 7);
      const month = tally.get(key) ?? { withdrawn: 0, received: 0, spent: 0, unaccounted: 0 };
      tally.set(key, month);
      const amount2 = cents(Math.abs(m.amount));
      if (m.kind === "withdrawal") {
        month.withdrawn += amount2;
        month.unaccounted += cents(m.left);
      } else if (m.kind === "received") month.received += amount2;
      else month.spent += amount2;
    }
    const months = {};
    for (const [key, m] of tally) {
      months[key] = { withdrawn: m.withdrawn / 100, received: m.received / 100, spent: m.spent / 100, unaccounted: m.unaccounted / 100 };
    }
    return { months, movements };
  }

  // src/engine/paybacks.ts
  var cents2 = (amount2) => Math.round(amount2 * 100);
  var compare4 = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  function countPaybacks(originals, stored, categories) {
    const marks = /* @__PURE__ */ new Map();
    const ignored = [];
    const payers = originals.filter((p) => p.paysBack?.length).sort((a, b) => compare4(a.date.slice(0, 10), b.date.slice(0, 10)) || compare4(a.id, b.id));
    if (!payers.length) return { marks, ignored };
    const byId = new Map(stored.map((p) => [p.id, p]));
    const originalIds = new Set(originals.map((p) => p.id));
    const transfers = new Set(categories.filter((c) => c.excludeFromTotals).map((c) => c.name));
    const isTransfer = (p) => p.category != null && transfers.has(p.category);
    const received = /* @__PURE__ */ new Map();
    for (const original of payers) {
      const payer = byId.get(original.id);
      const payerReason = !payer ? "payer-not-counted" : payer.amount <= 0 ? "payer-not-money-in" : isTransfer(payer) ? "payer-transfer" : payer.currency !== "EUR" ? "payer-not-euros" : null;
      if (!payer || payerReason) {
        for (const link of original.paysBack) ignored.push({ from: original.id, to: link.payment, reason: payerReason ?? "payer-not-counted" });
        continue;
      }
      let paid = 0;
      for (const link of original.paysBack) {
        const target = byId.get(link.payment);
        const reason = !target ? originalIds.has(link.payment) ? "target-not-counted" : "target-missing" : target.amount >= 0 ? "target-not-money-out" : isTransfer(target) ? "target-transfer" : isCashWithdrawal(target) ? "target-withdrawal" : target.currency !== "EUR" ? "target-not-euros" : !Number.isFinite(link.amount) || link.amount <= 0 || cents2(link.amount) <= 0 || !Number.isSafeInteger(cents2(link.amount)) || Math.abs(link.amount - cents2(link.amount) / 100) > 1e-9 ? "invalid-amount" : null;
        if (!target || reason) {
          ignored.push({ from: original.id, to: link.payment, reason: reason ?? "target-missing" });
          continue;
        }
        const requested = cents2(link.amount);
        const got = received.get(target.id) ?? 0;
        const applied = Math.min(requested, cents2(payer.amount) - paid, -cents2(target.amount) - got);
        if (applied < requested) ignored.push({ from: original.id, to: link.payment, reason: "clamped", amount: (requested - applied) / 100 });
        if (applied <= 0) continue;
        paid += applied;
        received.set(target.id, got + applied);
        const payerMarks = marks.get(original.id) ?? {};
        payerMarks.counted = (cents2(payer.amount) - paid) / 100;
        (payerMarks.paysBack ?? (payerMarks.paysBack = [])).push({ payment: target.id, amount: applied / 100 });
        marks.set(original.id, payerMarks);
        const targetMarks = marks.get(target.id) ?? {};
        targetMarks.counted = (cents2(target.amount) + got + applied) / 100;
        targetMarks.paidBack = (got + applied) / 100;
        (targetMarks.paidBackBy ?? (targetMarks.paidBackBy = [])).push({ payment: original.id, amount: applied / 100 });
        marks.set(target.id, targetMarks);
      }
    }
    return { marks, ignored };
  }

  // src/engine/balances.ts
  var cents3 = (amount2) => Math.round(amount2 * 100);
  function chainClosing(rows) {
    const degree = /* @__PURE__ */ new Map();
    const neighbours = /* @__PURE__ */ new Map();
    for (const row of rows) {
      const after = cents3(row.balance);
      const before = after - cents3(row.amount);
      degree.set(before, (degree.get(before) ?? 0) + 1);
      degree.set(after, (degree.get(after) ?? 0) - 1);
      const outgoing = neighbours.get(before) ?? [];
      outgoing.push(after);
      neighbours.set(before, outgoing);
      const incoming = neighbours.get(after) ?? [];
      incoming.push(before);
      neighbours.set(after, incoming);
    }
    const pending = [cents3(rows[0].balance)];
    const visited = /* @__PURE__ */ new Set();
    while (pending.length) {
      const value = pending.pop();
      if (visited.has(value)) continue;
      visited.add(value);
      for (const next of neighbours.get(value) ?? []) {
        if (!visited.has(next)) pending.push(next);
      }
    }
    if (visited.size !== degree.size) return null;
    const starts = [...degree].filter(([, value]) => value === 1);
    const ends = [...degree].filter(([, value]) => value === -1);
    if ([...degree.values()].some((value) => Math.abs(value) > 1)) return null;
    if (starts.length === 1 && ends.length === 1) return ends[0][0] / 100;
    if (degree.size === 1) return rows[0].balance;
    return null;
  }
  function closing(rows) {
    const hasOrder = rows.every((row) => Number.isSafeInteger(row.statementOrder)) && new Set(rows.map((row) => row.statementOrder)).size === rows.length;
    if (hasOrder) {
      const ordered = rows.slice().sort((a, b) => a.statementOrder - b.statementOrder);
      const uncertain = ordered.some((row, i2) => i2 > 0 && cents3(row.balance) - cents3(row.amount) !== cents3(ordered[i2 - 1].balance));
      return { balance: ordered[ordered.length - 1].balance, uncertain };
    }
    const derived = chainClosing(rows);
    return {
      balance: derived ?? rows[rows.length - 1].balance,
      uncertain: derived === null
    };
  }
  function accountDayClosings(payments) {
    const accounts2 = /* @__PURE__ */ new Map();
    for (const payment of payments) {
      if (payment.balance == null) continue;
      if (!Number.isFinite(payment.balance)) throw new Error(`Payment ${payment.id}: the balance is not a number`);
      const accountId = payment.accountId ?? null;
      const days = accounts2.get(accountId) ?? /* @__PURE__ */ new Map();
      const day2 = payment.date.slice(0, 10);
      const rows = days.get(day2) ?? [];
      rows.push(payment);
      days.set(day2, rows);
      accounts2.set(accountId, days);
    }
    const result = [];
    for (const [accountId, days] of accounts2) {
      for (const [date2, rows] of days) result.push({ accountId, date: date2, ...closing(rows) });
    }
    return result.sort((a, b) => a.date.localeCompare(b.date) || (a.accountId ?? "").localeCompare(b.accountId ?? ""));
  }
  function accountBalanceSeries(payments, months) {
    const closings = accountDayClosings(payments);
    const known = /* @__PURE__ */ new Map();
    const sum = () => known.size ? [...known.values()].reduce((total, value) => total + value, 0) / 100 : null;
    const balanceByDay = {};
    let index = 0;
    const firstDay = months.length ? `${months[0].key}-01` : "";
    while (index < closings.length && closings[index].date < firstDay) {
      const row = closings[index++];
      known.set(row.accountId, cents3(row.balance));
    }
    const openingBalance = sum();
    for (const month of months) {
      for (let d = 1; d <= month.days; d++) {
        const day2 = `${month.key}-${String(d).padStart(2, "0")}`;
        while (index < closings.length && closings[index].date <= day2) {
          const row = closings[index++];
          known.set(row.accountId, cents3(row.balance));
        }
        balanceByDay[day2] = sum();
      }
    }
    const uncertain = closings.filter((row) => row.uncertain).map(({ date: date2, accountId }) => ({ date: date2, accountId }));
    return { balanceByDay, openingBalance, ...uncertain.length ? { balanceUncertainDays: uncertain } : {} };
  }

  // src/engine/source.ts
  var UNCATEGORISED = Object.freeze({ name: "Uncategorised", icon: "CircleHelp", color: "#9ca3af", kind: "spend" });
  var MONTH_ABBR = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var pad = (n) => String(n).padStart(2, "0");
  var byDate = (a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : 0;
  function checked3(transactions) {
    for (const p of transactions) {
      if (!parseDay(p.date)) throw new Error(`Payment ${p.id}: the date is not an ISO date (YYYY-MM-DD)`);
      if (typeof p.amount !== "number" || !Number.isFinite(p.amount)) throw new Error(`Payment ${p.id}: the amount is not a number`);
    }
    return [...transactions].sort(byDate);
  }
  var counted = (ordered) => foldPaypalConversions(ordered.filter((p) => !isPaypalBankFunding(p)));
  function buildDashboardSource(input) {
    const today = parseDay(input.today);
    if (!today) throw new Error("today is not an ISO date (YYYY-MM-DD)");
    const ordered = checked3(input.transactions);
    const stored = counted(ordered).rows;
    const paybacks = countPaybacks(input.transactions, stored, input.categories);
    const storedPayments = new Set(stored);
    const fromReceipts = input.receipts ? countReceipts(stored, input.receipts, new Set(input.transactions.map((p) => p.id))) : null;
    const payments = fromReceipts?.rows.length ? withReceiptRows(stored, fromReceipts.rows) : stored;
    const known = new Set(input.categories.map((c) => c.name));
    const nameOf2 = (category) => category != null && known.has(category) ? category : null;
    const categoryOf = (p) => nameOf2(p.category);
    const net = /* @__PURE__ */ new Map();
    let hasUncategorised = false;
    for (const p of payments) {
      const category = categoryOf(p);
      if (category === null) hasUncategorised = true;
      const name = category ?? UNCATEGORISED.name;
      const amount2 = (storedPayments.has(p) ? paybacks.marks.get(p.id)?.counted : void 0) ?? p.amount;
      net.set(name, (net.get(name) ?? 0) + Math.round(amount2 * 100));
    }
    const categories = input.categories.map((c) => ({
      name: c.name,
      icon: c.icon,
      color: c.color,
      kind: c.excludeFromTotals ? "transfer" : c.side ?? ((net.get(c.name) ?? 0) > 0 ? "income" : "spend"),
      ...c.otherSide && !c.excludeFromTotals ? { otherSide: true } : {}
    }));
    if (hasUncategorised && !known.has(UNCATEGORISED.name)) categories.push({ ...UNCATEGORISED });
    const transactions = payments.map((p) => ({
      id: p.id,
      date: p.date.slice(0, 10),
      amount: p.amount,
      categoryName: categoryOf(p) ?? UNCATEGORISED.name,
      tags: [...p.tags ?? []],
      // extra ("Add") categories: shown there, never re-summed into totals
      place: p.counterparty || p.description,
      city: p.city ?? "",
      // Receipts only (briefs 30, 32): marks only when receipts are given, so the server's JSON stays as it was.
      ...p.receiptId !== void 0 ? { receiptId: p.receiptId } : {},
      ...p.provisional ? { provisional: true } : {},
      ...p.coveredBy ? { coveredBy: [...p.coveredBy] } : {},
      ...fromReceipts?.withdrawals.has(p) ? { cashWithdrawal: true } : {},
      // Apply only to stored payments, even if a receipt happens to have the same id.
      ...storedPayments.has(p) ? paybacks.marks.get(p.id) : void 0
    }));
    const months = [];
    if (payments.length) {
      const first = parseDay(payments[0].date);
      const last2 = parseDay(payments[payments.length - 1].date);
      let y = first.y, m = first.m - 1;
      while (y < last2.y || y === last2.y && m <= last2.m - 1) {
        const isCurrent = y === today.y && m === today.m - 1;
        months.push({
          key: `${y}-${pad(m + 1)}`,
          label: `${MONTH_ABBR[m]} ${y}`,
          short: MONTH_ABBR[m],
          year: y,
          month: m,
          days: isCurrent ? today.d : daysInMonth(y, m + 1),
          partial: isCurrent
        });
        m++;
        if (m > 11) {
          m = 0;
          y++;
        }
      }
    }
    const balances2 = accountBalanceSeries(input.transactions, months);
    return {
      categories,
      months,
      transactions,
      ...balances2,
      databaseCategoryNames: input.categories.map((c) => c.name),
      // The Cash page (brief 32): a view, counted nowhere.
      ...fromReceipts ? { cash: cashView(fromReceipts, (category) => nameOf2(category) ?? UNCATEGORISED.name) } : {},
      ...paybacks.ignored.length ? { paybacksIgnored: paybacks.ignored } : {}
    };
  }

  // src/engine/readers/decode.ts
  var WINDOWS_1252_HIGH = [
    8364,
    129,
    8218,
    402,
    8222,
    8230,
    8224,
    8225,
    710,
    8240,
    352,
    8249,
    338,
    141,
    381,
    143,
    144,
    8216,
    8217,
    8220,
    8221,
    8226,
    8211,
    8212,
    732,
    8482,
    353,
    8250,
    339,
    157,
    382,
    376
  ];
  function fromCodePoints(points) {
    let text3 = "";
    for (let i2 = 0; i2 < points.length; i2 += 8192) text3 += String.fromCodePoint(...points.slice(i2, i2 + 8192));
    return text3;
  }
  function utf8(bytes, start) {
    const points = [];
    for (let i2 = start; i2 < bytes.length; ) {
      const b = bytes[i2];
      if (b < 128) {
        points.push(b);
        i2++;
        continue;
      }
      let need, cp, min;
      if (b >= 194 && b <= 223) {
        need = 1;
        cp = b & 31;
        min = 128;
      } else if (b >= 224 && b <= 239) {
        need = 2;
        cp = b & 15;
        min = 2048;
      } else if (b >= 240 && b <= 244) {
        need = 3;
        cp = b & 7;
        min = 65536;
      } else return null;
      for (let k = 1; k <= need; k++) {
        const c = bytes[i2 + k];
        if (c === void 0 || (c & 192) !== 128) return null;
        cp = cp << 6 | c & 63;
      }
      if (cp < min || cp > 1114111 || cp >= 55296 && cp <= 57343) return null;
      points.push(cp);
      i2 += need + 1;
    }
    return fromCodePoints(points);
  }
  function windows1252(bytes) {
    const points = new Array(bytes.length);
    for (let i2 = 0; i2 < bytes.length; i2++) {
      const b = bytes[i2];
      points[i2] = b >= 128 && b <= 159 ? WINDOWS_1252_HIGH[b - 128] : b;
    }
    return fromCodePoints(points);
  }
  var LATIN_15 = {
    164: 8364,
    166: 352,
    168: 353,
    180: 381,
    184: 382,
    188: 338,
    189: 339,
    190: 376
  };
  function latin15(bytes) {
    let euro = false;
    for (let i2 = 0; i2 < bytes.length; i2++) {
      if (bytes[i2] >= 128 && bytes[i2] <= 159) return null;
      if (bytes[i2] === 164) euro = true;
    }
    if (!euro) return null;
    const points = new Array(bytes.length);
    for (let i2 = 0; i2 < bytes.length; i2++) points[i2] = LATIN_15[bytes[i2]] ?? bytes[i2];
    return fromCodePoints(points);
  }
  function utf16(bytes, littleEndian) {
    const units = [];
    for (let i2 = 2; i2 + 1 < bytes.length; i2 += 2) {
      units.push(littleEndian ? bytes[i2] | bytes[i2 + 1] << 8 : bytes[i2] << 8 | bytes[i2 + 1]);
    }
    let text3 = "";
    for (let i2 = 0; i2 < units.length; i2 += 8192) text3 += String.fromCharCode(...units.slice(i2, i2 + 8192));
    return text3;
  }
  function decodeBankFileWithEncoding(bytes) {
    if (bytes[0] === 255 && bytes[1] === 254) return { text: utf16(bytes, true), encoding: "utf-16le" };
    if (bytes[0] === 254 && bytes[1] === 255) return { text: utf16(bytes, false), encoding: "utf-16be" };
    const bom = bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191;
    const text3 = utf8(bytes, bom ? 3 : 0);
    if (text3 !== null) return { text: text3, encoding: "utf-8" };
    const latin = latin15(bytes);
    if (latin !== null) return { text: latin, encoding: "iso-8859-15" };
    return { text: windows1252(bytes), encoding: "windows-1252" };
  }
  function decodeBankFile(bytes) {
    return decodeBankFileWithEncoding(bytes).text;
  }

  // src/engine/readers/archive.ts
  var import_fast_xml_parser2 = __toESM(require_fxp(), 1);

  // src/engine/readers/csv.ts
  var SEPARATORS = [";", ",", "	", "|"];
  function splitCsv(text3, separator) {
    return inspectCsv(text3, separator).rows;
  }
  function inspectCsv(text3, separator) {
    const rows = [];
    let row = [];
    let field2 = "";
    let quoted = false;
    let fieldStarted = false;
    let closed = false, damaged = false;
    for (let i2 = 0; i2 < text3.length; i2++) {
      const ch = text3[i2];
      if (quoted) {
        if (ch === '"') {
          if (text3[i2 + 1] === '"') {
            field2 += '"';
            i2++;
          } else {
            quoted = false;
            closed = true;
          }
        } else field2 += ch;
        continue;
      }
      if (ch === '"' && !fieldStarted) {
        quoted = true;
        fieldStarted = true;
        continue;
      }
      if (ch === separator) {
        row.push(field2);
        field2 = "";
        fieldStarted = false;
        closed = false;
        continue;
      }
      if (ch === "\n" || ch === "\r") {
        if (ch === "\r" && text3[i2 + 1] === "\n") i2++;
        row.push(field2);
        rows.push(row);
        row = [];
        field2 = "";
        fieldStarted = false;
        closed = false;
        continue;
      }
      if (closed && ch.trim() !== "") damaged = true;
      field2 += ch;
      if (ch !== " ") fieldStarted = true;
    }
    if (field2 !== "" || row.length > 0) {
      row.push(field2);
      rows.push(row);
    }
    return { rows, damaged: damaged || quoted };
  }
  function countsPerLine(text3, separator, maxLines) {
    const counts = [];
    let count = 0, quoted = false;
    for (let i2 = 0; i2 < text3.length && counts.length < maxLines; i2++) {
      const ch = text3[i2];
      if (ch === '"') quoted = !quoted;
      else if (!quoted && ch === separator) count++;
      else if (!quoted && (ch === "\n" || ch === "\r")) {
        if (ch === "\r" && text3[i2 + 1] === "\n") i2++;
        counts.push(count);
        count = 0;
      }
    }
    if (counts.length < maxLines && count > 0) counts.push(count);
    return counts;
  }
  function detectSeparator(text3) {
    let best = ";", bestScore = -1;
    for (const separator of SEPARATORS) {
      const counts = countsPerLine(text3, separator, 200).filter((n) => n > 0);
      const frequency = /* @__PURE__ */ new Map();
      for (const n of counts) frequency.set(n, (frequency.get(n) ?? 0) + 1);
      let score = 0;
      for (const [n, lines] of frequency) if (n >= 1 && lines * Math.min(n, 4) > score) score = lines * Math.min(n, 4);
      if (score > bestScore) {
        best = separator;
        bestScore = score;
      }
    }
    return best;
  }

  // src/engine/readers/ids.ts
  var hashId = (fields2) => sha1(fields2).slice(0, 24);
  function withOccurrences(candidates) {
    const seen = /* @__PURE__ */ new Map();
    return candidates.map(({ id, fields: fields2 }) => {
      const occurrence = (seen.get(id) ?? 0) + 1;
      seen.set(id, occurrence);
      return occurrence === 1 ? id : hashId(`${fields2}|${occurrence}`);
    });
  }
  var bookingIds = (fields2) => withOccurrences(fields2.map((f) => ({ id: hashId(f), fields: f })));

  // src/engine/readers/values.ts
  var DATE_FORMATS = ["DD.MM.YYYY", "DD.MM.YY", "YYYY-MM-DD", "DD/MM/YYYY", "MM/DD/YYYY", "DD-MM-YYYY", "YYYYMMDD"];
  var DATE_PATTERNS = {
    // order: the match groups holding year, month, day. A time after the date ("2024-01-05 10:22:33") is ignored.
    "DD.MM.YYYY": { re: /^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:$|[\sT,])/, order: [3, 2, 1] },
    "DD.MM.YY": { re: /^(\d{1,2})\.(\d{1,2})\.(\d{2})(?:$|[\sT,])/, order: [3, 2, 1] },
    "YYYY-MM-DD": { re: /^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|[\sT,])/, order: [1, 2, 3] },
    "DD/MM/YYYY": { re: /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:$|[\sT,])/, order: [3, 2, 1] },
    "MM/DD/YYYY": { re: /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:$|[\sT,])/, order: [3, 1, 2] },
    "DD-MM-YYYY": { re: /^(\d{1,2})-(\d{1,2})-(\d{4})(?:$|[\sT,])/, order: [3, 2, 1] },
    "YYYYMMDD": { re: /^(\d{4})(\d{2})(\d{2})$/, order: [1, 2, 3] }
  };
  function parseDate(value, format) {
    const { re, order } = DATE_PATTERNS[format];
    const m = re.exec(value.trim());
    if (!m) return null;
    let year = +m[order[0]];
    if (m[order[0]].length === 2) year += 2e3;
    const month = +m[order[1]], day2 = +m[order[2]];
    if (year < 1970 || year > 2100 || month < 1 || month > 12 || day2 < 1) return null;
    if (day2 > new Date(Date.UTC(year, month, 0)).getUTCDate()) return null;
    return `${year}-${String(month).padStart(2, "0")}-${String(day2).padStart(2, "0")}`;
  }
  function columnDateFormats(values, preferred = []) {
    const order = [.../* @__PURE__ */ new Set([...preferred, "MM/DD/YYYY", ...DATE_FORMATS])];
    const counts = order.map((format) => values.filter((value) => parseDate(value, format) !== null).length);
    const most = Math.max(...counts);
    return most === 0 ? [] : order.filter((_, i2) => counts[i2] === most);
  }
  function canonicalAmount(negative, whole, fraction) {
    const intPart = whole.replace(/^0+(?=\d)/, "") || "0";
    let frac = fraction.padEnd(2, "0");
    while (frac.length > 2 && frac.endsWith("0")) frac = frac.slice(0, -1);
    const zero = /^0*$/.test(intPart + frac);
    return `${negative && !zero ? "-" : ""}${intPart}.${frac}`;
  }
  var MINUS = /^[-−–]/;
  function parseAmountStrict(value, format) {
    let v = value.trim().replace(/[\s  ']/g, "");
    v = v.replace(/^(EUR|USD|GBP|CHF|€|\$|£)/i, "").replace(/(EUR|USD|GBP|CHF|€|\$|£)$/i, "");
    let negative = false;
    if (/^\(.*\)$/.test(v)) {
      negative = true;
      v = v.slice(1, -1);
    }
    if (MINUS.test(v)) {
      negative = !negative;
      v = v.slice(1);
    } else if (v.startsWith("+")) v = v.slice(1);
    else if (/[-−]$/.test(v)) {
      negative = !negative;
      v = v.slice(0, -1);
    } else if (v.endsWith("+")) v = v.slice(0, -1);
    const [group, decimal] = format === "de" ? [".", ","] : [",", "."];
    const groupRe = group === "." ? "\\." : ",";
    const decimalRe = decimal === "." ? "\\." : ",";
    const re = new RegExp(`^(\\d{1,3}(?:${groupRe}\\d{3})+|\\d+)(?:${decimalRe}(\\d+))?$|^${decimalRe}(\\d+)$`);
    const m = re.exec(v);
    if (!m) return null;
    if (m[3] !== void 0) return canonicalAmount(negative, "0", m[3]);
    return canonicalAmount(negative, m[1].split(group).join(""), m[2] ?? "");
  }
  var isNegative = (amount2) => amount2.startsWith("-");
  var negate = (amount2) => isNegative(amount2) ? amount2.slice(1) : /^0\.0+$/.test(amount2) ? amount2 : `-${amount2}`;
  var absolute = (amount2) => isNegative(amount2) ? amount2.slice(1) : amount2;
  var SCALE = 5;
  function toUnits(amount2) {
    const negative = isNegative(amount2);
    const [whole, fraction = ""] = absolute(amount2).split(".");
    const units = BigInt(whole) * 10n ** BigInt(SCALE) + BigInt(fraction.padEnd(SCALE, "0").slice(0, SCALE) || "0");
    return negative ? -units : units;
  }
  function fromUnits(units) {
    const negative = units < 0n;
    const digits = (negative ? -units : units).toString().padStart(SCALE + 1, "0");
    return canonicalAmount(negative, digits.slice(0, -SCALE), digits.slice(-SCALE));
  }
  var addAmounts = (a, b) => fromUnits(toUnits(a) + toUnits(b));
  var sameAmount = (a, b) => toUnits(a) === toUnits(b);
  function normalizeIban(value) {
    const v = value.replace(/[\s'"]/g, "").toUpperCase();
    if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(v)) return null;
    const moved = v.slice(4) + v.slice(0, 4);
    let rest = 0;
    for (const ch of moved) {
      const n = ch >= "A" ? ch.charCodeAt(0) - 55 : +ch;
      rest = n >= 10 ? (rest * 100 + n) % 97 : (rest * 10 + n) % 97;
    }
    return rest === 1 ? v : null;
  }
  function headerKey(name) {
    return name.normalize("NFC").toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").replace(/€/g, "eur").replace(/[^a-z0-9]/g, "");
  }
  function cleanText(...parts) {
    return parts.map((p) => (p ?? "").replace(/\s+/g, " ").trim()).filter(Boolean).join(" ");
  }
  var SEPA_KEYS = /(EREF|KREF|MREF|CRED|DEBT|SVWZ|ABWA|ABWE|COAM|OAMT|IBAN|BIC)\+/g;
  function sepaPaymentText(text3) {
    const keys = [...text3.matchAll(SEPA_KEYS)];
    const svwz = keys.findIndex((m) => m[1] === "SVWZ");
    if (svwz < 0) return cleanText(text3.slice(0, keys[0]?.index ?? text3.length));
    const start = keys[svwz].index + 5;
    const end = keys[svwz + 1]?.index ?? text3.length;
    return cleanText(text3.slice(start, end));
  }

  // src/engine/readers/table.ts
  var BankFileError = class extends Error {
    constructor(code, message) {
      super(message);
      __publicField(this, "code", code);
      this.name = "BankFileError";
    }
  };
  function checkedCsvRows(text3, separator) {
    const result = inspectCsv(text3.replace(/^\uFEFF/, ""), separator);
    if (result.damaged) throw new BankFileError("unknown", "The file has a broken or unfinished quoted field. Download it again.");
    return result.rows;
  }
  function trimRow(row) {
    let end = row.length;
    while (end > 0 && row[end - 1].trim() === "") end--;
    return row.slice(0, end).map((cell2) => cell2.trim());
  }
  function findHeaderRow(rows, keys) {
    for (let i2 = 0; i2 < Math.min(rows.length, 60); i2++) {
      const present = new Set(rows[i2].map(headerKey));
      if (keys.every((group) => group.some((k) => present.has(k)))) return i2;
    }
    return -1;
  }
  function findTable(rows, layout2) {
    if (layout2.header.length === 0) {
      const first = rows.find((r) => r.some((v) => v.trim() !== ""));
      const fits = first !== void 0 && (layout2.columnCount === void 0 || first.length === layout2.columnCount) && parseDate(cell(first, layout2.columns.date), layout2.dateFormat) !== null;
      return fits ? -1 : null;
    }
    const want = trimRow(layout2.header).map(headerKey).join("");
    for (let i2 = 0; i2 < Math.min(rows.length, 60); i2++) {
      if (trimRow(rows[i2]).map(headerKey).join("") === want) return i2;
    }
    return null;
  }
  function uniqueHeader(header) {
    const seen = /* @__PURE__ */ new Map();
    return header.map((name, i2) => {
      const base = name.trim() || `Column ${i2 + 1}`;
      const n = (seen.get(base) ?? 0) + 1;
      seen.set(base, n);
      return n === 1 ? base : `${base} (${n})`;
    });
  }
  function findIban(text3) {
    for (const m of text3.toUpperCase().matchAll(/[A-Z]{2}\d{2}(?:\s?[A-Z0-9]){11,30}/g)) {
      const compact = m[0].replace(/\s/g, "");
      for (let len = compact.length; len >= 15; len--) {
        const iban = normalizeIban(compact.slice(0, len));
        if (iban) return iban;
      }
    }
    return void 0;
  }
  function labelledPart(text3, label, labels) {
    const escape = (l) => l.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
    const start = label === "" ? { index: 0, 0: "" } : new RegExp(`(?:^|\\s)${escape(label)}\\s*[:.]`, "i").exec(text3);
    if (!start) return "";
    const rest = text3.slice(start.index + start[0].length);
    const next = new RegExp(`(?:^|\\s)(?:${labels.map(escape).join("|")})\\s*[:.]`, "i").exec(rest);
    return cleanText(next ? rest.slice(0, next.index) : rest);
  }
  var DEBIT_MARK = /^(s|soll|d|db|dbit|debit|belastung|lastschrift|-)$/i;
  var CREDIT_MARK = /^(h|haben|c|cr|crdt|credit|gutschrift|\+)$/i;
  function signMark(value) {
    const v = value.trim();
    return DEBIT_MARK.test(v) ? "debit" : CREDIT_MARK.test(v) ? "credit" : null;
  }
  function accountName(bank, iban) {
    return iban ? `${bank} \u2022\u2022${iban.slice(-4)}` : bank;
  }
  function cell(row, index) {
    return index === void 0 ? "" : (row[index] ?? "").trim();
  }
  function readCsv(text3, layout2) {
    const rows = checkedCsvRows(text3, layout2.separator);
    if (rows.length === 0) throw new BankFileError("empty", "The file is empty.");
    const headerIndex = findTable(rows, layout2);
    if (headerIndex === null) throw new BankFileError("headerMismatch", "The file's header row does not match the layout.");
    return readTable(rows, headerIndex, layout2);
  }
  function readTable(rows, headerIndex, layout2) {
    const c = layout2.columns;
    const width = layout2.columnCount ?? Math.max(0, ...rows.slice(0, 50).map((r) => r.length));
    const names2 = uniqueHeader(headerIndex >= 0 ? rows[headerIndex].map((h) => h.trim()) : new Array(width).fill(""));
    const transactions = [];
    const idFields = [];
    const references = [];
    let skipped = 0;
    let unreadable = 0;
    let ownIban2;
    const accountColumn = layout2.header.findIndex((h) => /^(kontoname|accountname|bezeichnungauftragskonto|kontonummerauftragskonto)$/.test(headerKey(h)));
    let ownAccount;
    const amountHeader = layout2.header[c.amount ?? c.debit ?? c.credit ?? -1] ?? "";
    const headerCurrencies = [...new Set(amountHeader.toUpperCase().match(/\b(EUR|USD|GBP|CHF|JPY|CAD|AUD|CNY|DKK|NOK|SEK|PLN|CZK|HUF)\b/g) ?? [])];
    if (headerCurrencies.length > 1 && c.currency === void 0) {
      throw new BankFileError("unknown", "The amount column names several currencies without identifying each payment's currency.");
    }
    let currency = layout2.currency ?? headerCurrencies[0] ?? "EUR";
    const skip = (layout2.skipStatus ?? []).map((s) => s.toLowerCase());
    const keep = (layout2.keepStatus ?? []).map((s) => s.toLowerCase());
    const dateHeader = headerIndex >= 0 ? headerKey(rows[headerIndex][c.date] ?? "") : "";
    const datedRows = rows.slice(headerIndex + 1).filter((row) => DATE_FORMATS.some((f) => parseDate(cell(row, c.date), f) !== null));
    const expectedWidth = Math.min(
      layout2.columnCount ?? layout2.header.length,
      datedRows.reduce((n, row) => Math.max(n, row.length), 0)
    );
    for (let r = headerIndex + 1; r < rows.length; r++) {
      const row = rows[r];
      if (row.every((v) => v.trim() === "")) continue;
      if (row.length < expectedWidth && DATE_FORMATS.some((f) => parseDate(cell(row, c.date), f) !== null)) {
        throw new BankFileError("unknown", "A payment row is cut off or has missing columns. Download the file again.");
      }
      if (dateHeader && headerKey(cell(row, c.date)) === dateHeader) {
        throw new BankFileError("unknown", "This file contains several payment tables or accounts. Export each account separately.");
      }
      const keys = row.map(headerKey);
      if (keys.some((k) => /^(date|bookingdate|buchungstag|buchungsdatum|buchung|umsatztag|belegdatum)$/.test(k)) && keys.some((k) => /^(amount|amounteur|betrag|betrageur|umsatzineur|debit|soll)$/.test(k))) {
        throw new BankFileError("unknown", "This file contains several payment tables or accounts. Export each account separately.");
      }
      const date2 = parseDate(cell(row, c.date), layout2.dateFormat);
      const status = cell(row, c.status).toLowerCase();
      if (c.status !== void 0 && (skip.some((s) => status.includes(s)) || keep.length > 0 && !keep.some((s) => status.includes(s)))) {
        skipped++;
        continue;
      }
      if (!date2) {
        skipped++;
        const dateCell = cell(row, c.date);
        const notice = /^(offen|pending|vorgemerkt|--)$/.test(dateCell.toLowerCase()) || /^(summe|total|saldo|anfangssaldo|endsaldo|alter kontostand|neuer kontostand)\b/i.test(cleanText(...row));
        if (!notice && DATE_FORMATS.some((f) => parseDate(dateCell, f) !== null)) {
          throw new BankFileError("unknown", "The date column mixes incompatible formats. Check how its dates are written.");
        }
        if (!notice) unreadable++;
        continue;
      }
      let amount2 = null;
      if (c.amount !== void 0) {
        amount2 = parseAmountStrict(cell(row, c.amount), layout2.numberFormat);
        const mark = signMark(cell(row, c.sign));
        if (amount2 && c.sign !== void 0) {
          if (mark === "debit") amount2 = negate(absolute(amount2));
          else if (mark === "credit") amount2 = absolute(amount2);
        }
      } else {
        const debit = parseAmountStrict(cell(row, c.debit), layout2.numberFormat);
        const credit = parseAmountStrict(cell(row, c.credit), layout2.numberFormat);
        if (debit && !/^0\.0+$/.test(debit)) amount2 = negate(absolute(debit));
        else if (credit) amount2 = absolute(credit);
        else if (debit) amount2 = debit;
      }
      if (!amount2) {
        skipped++;
        unreadable++;
        continue;
      }
      if (layout2.invertSign) amount2 = negate(amount2);
      for (const j of c.fees ?? []) {
        const fee = parseAmountStrict(cell(row, j), layout2.numberFormat);
        if (fee) amount2 = addAmounts(amount2, negate(absolute(fee)));
      }
      for (const j of c.addAmounts ?? []) {
        const extra = parseAmountStrict(cell(row, j), layout2.numberFormat);
        if (extra) amount2 = addAmounts(amount2, extra);
      }
      if (/^-?0\.0+$/.test(amount2)) {
        skipped++;
        continue;
      }
      const out = amount2.startsWith("-");
      let counterparty = (out ? cell(row, c.payee) || cell(row, c.payer) : cell(row, c.payer) || cell(row, c.payee)) || (c.counterparty ?? []).map((i2) => cell(row, i2)).find(Boolean) || "";
      let paymentText = sepaPaymentText(cleanText(...(c.text ?? []).map((i2) => cell(row, i2))));
      if (layout2.labelledText) {
        const { labels, counterparty: names3, text: texts2 } = layout2.labelledText;
        const whole = paymentText;
        counterparty || (counterparty = names3.map((l) => labelledPart(whole, l, labels)).find(Boolean) ?? "");
        const labelled = texts2.map((l) => labelledPart(whole, l, labels)).find(Boolean);
        if (labelled !== void 0) paymentText = labelled;
        else if (counterparty) paymentText = "";
      }
      let description = paymentText || cleanText(cell(row, c.kind)) || cleanText(counterparty) || "(no description)";
      if (layout2.idStyle === "vrbank") {
        description = (c.text ?? []).map((i2) => cell(row, i2)).find(Boolean) || cell(row, c.kind) || "(no description)";
      }
      const valueDate = c.valueDate !== void 0 ? parseDate(cell(row, c.valueDate), layout2.dateFormat) : void 0;
      const balance = c.balance !== void 0 ? parseAmountStrict(cell(row, c.balance), layout2.numberFormat) : void 0;
      const rowCurrency = /^[A-Za-z]{3}$/.test(cell(row, c.currency)) ? cell(row, c.currency).toUpperCase() : currency;
      currency = rowCurrency;
      const rowIban = c.accountIban !== void 0 ? normalizeIban(cell(row, c.accountIban)) ?? void 0 : void 0;
      const rowAccount = accountColumn >= 0 ? cell(row, accountColumn) : "";
      if (ownIban2 && rowIban && ownIban2 !== rowIban || ownAccount && rowAccount && ownAccount !== rowAccount) {
        throw new BankFileError("unknown", "This file contains payments from several accounts. Export each account separately.");
      }
      ownIban2 ?? (ownIban2 = rowIban);
      ownAccount ?? (ownAccount = rowAccount || void 0);
      const counterpartyIban = c.iban !== void 0 ? normalizeIban(cell(row, c.iban)) : null;
      const raw = {};
      names2.forEach((name2, i2) => {
        raw[name2] = (row[i2] ?? "").trim();
      });
      transactions.push({
        bookingDate: `${date2}T00:00:00.000Z`,
        ...c.valueDate !== void 0 ? { valueDate: valueDate ? `${valueDate}T00:00:00.000Z` : null } : {},
        amount: amount2,
        ...c.balance !== void 0 ? { balance: balance ?? null } : {},
        currency: rowCurrency,
        description,
        counterparty: cleanText(counterparty) || null,
        ...counterpartyIban ? { counterpartyIban } : {},
        raw
      });
      if (layout2.idStyle === "vrbank") {
        let legacy = parseAmount(cell(row, c.amount));
        if (/^(s|d|soll)/i.test(cell(row, c.sign)) && !legacy.startsWith("-")) legacy = `-${legacy}`;
        idFields.push(`${date2}T00:00:00.000Z|${legacy}|${description}|${counterparty}`);
      } else {
        idFields.push([
          date2,
          amount2,
          ...[c.payer, c.payee, ...c.counterparty ?? [], ...c.text ?? []].map((i2) => cleanText(cell(row, i2))),
          cell(row, c.iban).replace(/\s/g, "")
        ].join("|"));
      }
      references.push(cell(row, c.reference).replace(/^'+|'+$/g, "") || void 0);
    }
    if (transactions.length === 0) throw new BankFileError("noTable", "No readable booked payments were found in this file.");
    if (unreadable > transactions.length) throw new BankFileError("unknown", "Most payment rows could not be read. Check the file's columns and formats.");
    if (!ownIban2) for (const row of rows.slice(0, Math.max(headerIndex, 0))) ownIban2 ?? (ownIban2 = findIban(row.join(" ")));
    const hashed = bookingIds(idFields);
    const ids = withReferences(references, hashed);
    const name = layout2.name ?? "Bank";
    const account = { name: accountName(name, ownIban2), currency };
    if (ownIban2) account.iban = ownIban2;
    return {
      format: "csv",
      account,
      transactions: transactions.map((t, i2) => ({ externalId: ids[i2], ...t })),
      skipped,
      layout: layout2
    };
  }
  function withReferences(references, hashed) {
    const counts = /* @__PURE__ */ new Map();
    for (const ref of references) if (ref) counts.set(ref, (counts.get(ref) ?? 0) + 1);
    return references.map((ref, i2) => ref && counts.get(ref) === 1 ? ref : hashed[i2]);
  }

  // node_modules/fflate/esm/browser.js
  var u8 = Uint8Array;
  var u16 = Uint16Array;
  var i32 = Int32Array;
  var fleb = new u8([
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    0,
    /* unused */
    0,
    0,
    /* impossible */
    0
  ]);
  var fdeb = new u8([
    0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13,
    /* unused */
    0,
    0
  ]);
  var clim = new u8([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]);
  var freb = function(eb, start) {
    var b = new u16(31);
    for (var i2 = 0; i2 < 31; ++i2) {
      b[i2] = start += 1 << eb[i2 - 1];
    }
    var r = new i32(b[30]);
    for (var i2 = 1; i2 < 30; ++i2) {
      for (var j = b[i2]; j < b[i2 + 1]; ++j) {
        r[j] = j - b[i2] << 5 | i2;
      }
    }
    return { b, r };
  };
  var _a = freb(fleb, 2);
  var fl = _a.b;
  var revfl = _a.r;
  fl[28] = 258, revfl[258] = 28;
  var _b = freb(fdeb, 0);
  var fd = _b.b;
  var revfd = _b.r;
  var rev = new u16(32768);
  for (i = 0; i < 32768; ++i) {
    x = (i & 43690) >> 1 | (i & 21845) << 1;
    x = (x & 52428) >> 2 | (x & 13107) << 2;
    x = (x & 61680) >> 4 | (x & 3855) << 4;
    rev[i] = ((x & 65280) >> 8 | (x & 255) << 8) >> 1;
  }
  var x;
  var i;
  var hMap = (function(cd, mb, r) {
    var s = cd.length;
    var i2 = 0;
    var l = new u16(mb);
    for (; i2 < s; ++i2) {
      if (cd[i2])
        ++l[cd[i2] - 1];
    }
    var le = new u16(mb);
    for (i2 = 1; i2 < mb; ++i2) {
      le[i2] = le[i2 - 1] + l[i2 - 1] << 1;
    }
    var co;
    if (r) {
      co = new u16(1 << mb);
      var rvb = 15 - mb;
      for (i2 = 0; i2 < s; ++i2) {
        if (cd[i2]) {
          var sv = i2 << 4 | cd[i2];
          var r_1 = mb - cd[i2];
          var v = le[cd[i2] - 1]++ << r_1;
          for (var m = v | (1 << r_1) - 1; v <= m; ++v) {
            co[rev[v] >> rvb] = sv;
          }
        }
      }
    } else {
      co = new u16(s);
      for (i2 = 0; i2 < s; ++i2) {
        if (cd[i2]) {
          co[i2] = rev[le[cd[i2] - 1]++] >> 15 - cd[i2];
        }
      }
    }
    return co;
  });
  var flt = new u8(288);
  for (i = 0; i < 144; ++i)
    flt[i] = 8;
  var i;
  for (i = 144; i < 256; ++i)
    flt[i] = 9;
  var i;
  for (i = 256; i < 280; ++i)
    flt[i] = 7;
  var i;
  for (i = 280; i < 288; ++i)
    flt[i] = 8;
  var i;
  var fdt = new u8(32);
  for (i = 0; i < 32; ++i)
    fdt[i] = 5;
  var i;
  var flrm = /* @__PURE__ */ hMap(flt, 9, 1);
  var fdrm = /* @__PURE__ */ hMap(fdt, 5, 1);
  var max = function(a) {
    var m = a[0];
    for (var i2 = 1; i2 < a.length; ++i2) {
      if (a[i2] > m)
        m = a[i2];
    }
    return m;
  };
  var bits = function(d, p, m) {
    var o = p / 8 | 0;
    return (d[o] | d[o + 1] << 8) >> (p & 7) & m;
  };
  var bits16 = function(d, p) {
    var o = p / 8 | 0;
    return (d[o] | d[o + 1] << 8 | d[o + 2] << 16) >> (p & 7);
  };
  var shft = function(p) {
    return (p + 7) / 8 | 0;
  };
  var slc = function(v, s, e) {
    if (s == null || s < 0)
      s = 0;
    if (e == null || e > v.length)
      e = v.length;
    return new u8(v.subarray(s, e));
  };
  var ec = [
    "unexpected EOF",
    "invalid block type",
    "invalid length/literal",
    "invalid distance",
    "stream finished",
    "no stream handler",
    ,
    "no callback",
    "invalid UTF-8 data",
    "extra field too long",
    "date not in range 1980-2099",
    "filename too long",
    "stream finishing",
    "invalid zip data"
    // determined by unknown compression method
  ];
  var err = function(ind, msg, nt) {
    var e = new Error(msg || ec[ind]);
    e.code = ind;
    if (Error.captureStackTrace)
      Error.captureStackTrace(e, err);
    if (!nt)
      throw e;
    return e;
  };
  var inflt = function(dat, st, buf, dict) {
    var sl = dat.length, dl = dict ? dict.length : 0;
    if (!sl || st.f && !st.l)
      return buf || new u8(0);
    var noBuf = !buf;
    var resize = noBuf || st.i != 2;
    var noSt = st.i;
    if (noBuf)
      buf = new u8(sl * 3);
    var cbuf = function(l2) {
      var bl = buf.length;
      if (l2 > bl) {
        var nbuf = new u8(Math.max(bl * 2, l2));
        nbuf.set(buf);
        buf = nbuf;
      }
    };
    var final = st.f || 0, pos = st.p || 0, bt = st.b || 0, lm = st.l, dm = st.d, lbt = st.m, dbt = st.n;
    var tbts = sl * 8;
    do {
      if (!lm) {
        final = bits(dat, pos, 1);
        var type = bits(dat, pos + 1, 3);
        pos += 3;
        if (!type) {
          var s = shft(pos) + 4, l = dat[s - 4] | dat[s - 3] << 8, t = s + l;
          if (t > sl) {
            if (noSt)
              err(0);
            break;
          }
          if (resize)
            cbuf(bt + l);
          buf.set(dat.subarray(s, t), bt);
          st.b = bt += l, st.p = pos = t * 8, st.f = final;
          continue;
        } else if (type == 1)
          lm = flrm, dm = fdrm, lbt = 9, dbt = 5;
        else if (type == 2) {
          var hLit = bits(dat, pos, 31) + 257, hcLen = bits(dat, pos + 10, 15) + 4;
          var tl = hLit + bits(dat, pos + 5, 31) + 1;
          pos += 14;
          var ldt = new u8(tl);
          var clt = new u8(19);
          for (var i2 = 0; i2 < hcLen; ++i2) {
            clt[clim[i2]] = bits(dat, pos + i2 * 3, 7);
          }
          pos += hcLen * 3;
          var clb = max(clt), clbmsk = (1 << clb) - 1;
          var clm = hMap(clt, clb, 1);
          for (var i2 = 0; i2 < tl; ) {
            var r = clm[bits(dat, pos, clbmsk)];
            pos += r & 15;
            var s = r >> 4;
            if (s < 16) {
              ldt[i2++] = s;
            } else {
              var c = 0, n = 0;
              if (s == 16)
                n = 3 + bits(dat, pos, 3), pos += 2, c = ldt[i2 - 1];
              else if (s == 17)
                n = 3 + bits(dat, pos, 7), pos += 3;
              else if (s == 18)
                n = 11 + bits(dat, pos, 127), pos += 7;
              while (n--)
                ldt[i2++] = c;
            }
          }
          var lt = ldt.subarray(0, hLit), dt = ldt.subarray(hLit);
          lbt = max(lt);
          dbt = max(dt);
          lm = hMap(lt, lbt, 1);
          dm = hMap(dt, dbt, 1);
        } else
          err(1);
        if (pos > tbts) {
          if (noSt)
            err(0);
          break;
        }
      }
      if (resize)
        cbuf(bt + 131072);
      var lms = (1 << lbt) - 1, dms = (1 << dbt) - 1;
      var lpos = pos;
      for (; ; lpos = pos) {
        var c = lm[bits16(dat, pos) & lms], sym = c >> 4;
        pos += c & 15;
        if (pos > tbts) {
          if (noSt)
            err(0);
          break;
        }
        if (!c)
          err(2);
        if (sym < 256)
          buf[bt++] = sym;
        else if (sym == 256) {
          lpos = pos, lm = null;
          break;
        } else {
          var add = sym - 254;
          if (sym > 264) {
            var i2 = sym - 257, b = fleb[i2];
            add = bits(dat, pos, (1 << b) - 1) + fl[i2];
            pos += b;
          }
          var d = dm[bits16(dat, pos) & dms], dsym = d >> 4;
          if (!d)
            err(3);
          pos += d & 15;
          var dt = fd[dsym];
          if (dsym > 3) {
            var b = fdeb[dsym];
            dt += bits16(dat, pos) & (1 << b) - 1, pos += b;
          }
          if (pos > tbts) {
            if (noSt)
              err(0);
            break;
          }
          if (resize)
            cbuf(bt + 131072);
          var end = bt + add;
          if (bt < dt) {
            var shift = dl - dt, dend = Math.min(dt, end);
            if (shift + bt < 0)
              err(3);
            for (; bt < dend; ++bt)
              buf[bt] = dict[shift + bt];
          }
          for (; bt < end; ++bt)
            buf[bt] = buf[bt - dt];
        }
      }
      st.l = lm, st.p = lpos, st.b = bt, st.f = final;
      if (lm)
        final = 1, st.m = lbt, st.d = dm, st.n = dbt;
    } while (!final);
    return bt != buf.length && noBuf ? slc(buf, 0, bt) : buf.subarray(0, bt);
  };
  var et = /* @__PURE__ */ new u8(0);
  var Inflate = /* @__PURE__ */ (function() {
    function Inflate2(opts, cb) {
      if (typeof opts == "function")
        cb = opts, opts = {};
      this.ondata = cb;
      var dict = opts && opts.dictionary && opts.dictionary.subarray(-32768);
      this.s = { i: 0, b: dict ? dict.length : 0 };
      this.o = new u8(32768);
      this.p = new u8(0);
      if (dict)
        this.o.set(dict);
    }
    Inflate2.prototype.e = function(c) {
      if (!this.ondata)
        err(5);
      if (this.d)
        err(4);
      if (!this.p.length)
        this.p = c;
      else if (c.length) {
        var n = new u8(this.p.length + c.length);
        n.set(this.p), n.set(c, this.p.length), this.p = n;
      }
    };
    Inflate2.prototype.c = function(final) {
      this.s.i = +(this.d = final || false);
      var bts = this.s.b;
      var dt = inflt(this.p, this.s, this.o);
      this.ondata(slc(dt, bts, this.s.b), this.d);
      this.o = slc(dt, this.s.b - 32768), this.s.b = this.o.length;
      this.p = slc(this.p, this.s.p / 8 | 0), this.s.p &= 7;
    };
    Inflate2.prototype.push = function(chunk, final) {
      this.e(chunk), this.c(final);
    };
    return Inflate2;
  })();
  var td = typeof TextDecoder != "undefined" && /* @__PURE__ */ new TextDecoder();
  var tds = 0;
  try {
    td.decode(et, { stream: true });
    tds = 1;
  } catch (e) {
  }
  var dutf8 = function(d) {
    for (var r = "", i2 = 0; ; ) {
      var c = d[i2++];
      var eb = (c > 127) + (c > 223) + (c > 239);
      if (i2 + eb > d.length)
        return { s: r, r: slc(d, i2 - 1) };
      if (!eb)
        r += String.fromCharCode(c);
      else if (eb == 3) {
        c = ((c & 15) << 18 | (d[i2++] & 63) << 12 | (d[i2++] & 63) << 6 | d[i2++] & 63) - 65536, r += String.fromCharCode(55296 | c >> 10, 56320 | c & 1023);
      } else if (eb & 1)
        r += String.fromCharCode((c & 31) << 6 | d[i2++] & 63);
      else
        r += String.fromCharCode((c & 15) << 12 | (d[i2++] & 63) << 6 | d[i2++] & 63);
    }
  };
  function strFromU8(dat, latin1) {
    if (latin1) {
      var r = "";
      for (var i2 = 0; i2 < dat.length; i2 += 16384)
        r += String.fromCharCode.apply(null, dat.subarray(i2, i2 + 16384));
      return r;
    } else if (td) {
      return td.decode(dat);
    } else {
      var _a2 = dutf8(dat), s = _a2.s, r = _a2.r;
      if (r.length)
        err(8);
      return s;
    }
  }

  // src/engine/readers/zip.ts
  var ZIP_MAX_BYTES = 50 * 1024 * 1024;
  var ZIP_MAX_ENTRIES = 2e3;
  var isZip = (b) => b[0] === 80 && b[1] === 75 && (b[2] === 3 && b[3] === 4 || b[2] === 5 && b[3] === 6);
  var bad = () => {
    throw new BankFileError("zip", "This ZIP archive is damaged or uses an unsupported ZIP format.");
  };
  var limit = () => {
    throw new BankFileError("zipLimit", "The ZIP archive exceeds 50 MB unpacked or 2,000 entries.");
  };
  var encrypted = () => {
    throw new BankFileError("zipEncrypted", "Encrypted ZIP files cannot be read. Export an unencrypted bank file.");
  };
  var crcTable = Array.from({ length: 256 }, (_, i2) => {
    let c = i2;
    for (let k = 0; k < 8; k++) c = c >>> 1 ^ (c & 1 ? 3988292384 : 0);
    return c;
  });
  var crc32 = (b) => {
    let c = 4294967295;
    for (const v of b) c = c >>> 8 ^ crcTable[(c ^ v) & 255];
    return (c ^ 4294967295) >>> 0;
  };
  function unzipBankFile(input) {
    const b = Uint8Array.from(input);
    const u162 = (p2) => {
      if (p2 < 0 || p2 + 2 > b.length) return bad();
      return b[p2] | b[p2 + 1] << 8;
    };
    const u32 = (p2) => u162(p2) + u162(p2 + 2) * 65536 >>> 0;
    const entryName = (start, length, flags) => {
      const bytes = b.subarray(start, start + length);
      if (!(flags & 2048)) return strFromU8(bytes, true).replace(/\\/g, "/");
      const decoded = decodeBankFileWithEncoding(bytes);
      if (decoded.encoding !== "utf-8") return bad();
      return decoded.text.replace(/\\/g, "/");
    };
    let end = b.length - 22;
    for (; end >= Math.max(0, b.length - 65557); end--) {
      if (u32(end) === 101010256 && end + 22 + u162(end + 20) === b.length) break;
    }
    if (end < 0 || u32(end) !== 101010256) return bad();
    if (u162(end + 4) || u162(end + 6) || u162(end + 8) !== u162(end + 10)) return bad();
    const count = u162(end + 10), directory = u32(end + 16);
    if (count > ZIP_MAX_ENTRIES) limit();
    if (directory + u32(end + 12) !== end) return bad();
    const entries = [];
    const names2 = /* @__PURE__ */ new Set();
    let p = directory, total = 0;
    for (let i2 = 0; i2 < count; i2++) {
      if (u32(p) !== 33639248) return bad();
      const flags = u162(p + 8), method = u162(p + 10), packed = u32(p + 20), size = u32(p + 24);
      const len = u162(p + 28), extra = u162(p + 30), comment = u162(p + 32), local = u32(p + 42);
      if (flags & 65) encrypted();
      total += size;
      if (total > ZIP_MAX_BYTES) limit();
      if (p + 46 + len + extra + comment > end || u162(p + 34) || local >= directory) return bad();
      const name = entryName(p + 46, len, flags);
      if (!name || name.startsWith("/") || name.split("/").includes("..") || names2.has(name)) return bad();
      names2.add(name);
      if (u32(local) !== 67324752) return bad();
      const localFlags = u162(local + 6);
      if (localFlags & 65) encrypted();
      const start = local + 30 + u162(local + 26) + u162(local + 28);
      if (localFlags !== flags || u162(local + 8) !== method || start + packed > directory || entryName(local + 30, u162(local + 26), flags) !== name) return bad();
      if (!(flags & 8) && (u32(local + 18) !== packed || u32(local + 22) !== size || u32(local + 14) !== u32(p + 16))) return bad();
      if (method !== 0 && method !== 8) return bad();
      entries.push({ name, size, packed, start, method, crc: u32(p + 16) });
      p += 46 + len + extra + comment;
    }
    if (p !== end) return bad();
    const result = /* @__PURE__ */ new Map();
    let actual = 0;
    for (const e of entries) {
      const chunks = [];
      let length = 0;
      const take = (chunk) => {
        length += chunk.length;
        actual += chunk.length;
        if (actual > ZIP_MAX_BYTES) limit();
        if (length > e.size) return bad();
        chunks.push(chunk);
      };
      try {
        if (e.method === 0) take(b.subarray(e.start, e.start + e.packed));
        else {
          const inflater = new Inflate(take);
          for (let n = 0; n < e.packed; n += 256) inflater.push(b.subarray(e.start + n, e.start + Math.min(n + 256, e.packed)), n + 256 >= e.packed);
        }
      } catch (error) {
        if (error instanceof BankFileError) throw error;
        return bad();
      }
      if (length !== e.size) return bad();
      const out = new Uint8Array(length);
      let at = 0;
      for (const chunk of chunks) {
        out.set(chunk, at);
        at += chunk.length;
      }
      if (crc32(out) !== e.crc) return bad();
      if (!e.name.endsWith("/") && !e.name.split("/").some((part) => part.startsWith(".") || part === "__MACOSX")) result.set(e.name, out);
    }
    return result;
  }

  // src/engine/readers/archive.ts
  var noBank = () => {
    throw new BankFileError("zipNoBankFile", "The ZIP archive contains no CAMT, MT940 or CSV bank files.");
  };
  var accounts = () => {
    throw new BankFileError("zipAccounts", "The ZIP archive contains different accounts or its files cannot be confirmed as one account. Export one account at a time.");
  };
  var layout = () => {
    throw new BankFileError("zipLayout", "A bank file inside this ZIP needs its columns confirmed. Import that file separately first.");
  };
  function archiveBankTexts(files, isBank) {
    const texts2 = [];
    for (const [name, bytes] of files) {
      if (isZip(bytes) || /\.(zip|xlsx|xls)$/i.test(name)) continue;
      const text3 = decodeBankFile(bytes);
      if (isBank(text3) || /\.(csv|sta|mta|mt940)$/i.test(name)) texts2.push(text3);
    }
    if (!texts2.length) return noBank();
    return texts2;
  }
  function memberAccounts(text3) {
    if (text3.trimStart().startsWith("<")) {
      const parser4 = new import_fast_xml_parser2.XMLParser({ ignoreAttributes: false, parseTagValue: false, removeNSPrefix: true });
      let root;
      try {
        root = parser4.parse(text3).Document;
      } catch {
        throw new BankFileError("camt", "This XML file could not be read.");
      }
      const container = root?.BkToCstmrStmt ?? root?.BkToCstmrAcctRpt ?? root?.BkToCstmrDbtCdtNtfctn;
      const statements = container?.Stmt ?? container?.Rpt ?? container?.Ntfctn ?? [];
      return [statements].flat().map((s) => String(s.Acct?.Id?.IBAN ?? s.Acct?.Id?.Othr?.Id ?? "").replace(/\s/g, "").toUpperCase());
    }
    return [...text3.matchAll(/^:25:(.+)$/gm)].map((m) => m[1].trim().replace(/\s/g, "").toUpperCase());
  }
  function readArchive(texts2, read2) {
    const files = texts2.map((text3) => {
      const ids = memberAccounts(text3);
      if (new Set(ids).size > 1) return accounts();
      return { file: read2(text3), own: ids[0] };
    });
    if (files.length === 1) return { ...files[0].file, transactions: [...files[0].file.transactions].sort((a, b) => a.bookingDate.localeCompare(b.bookingDate)) };
    if (files.some(({ file }) => file.needsLayout)) return layout();
    const identities = files.map(({ file, own }) => file.account?.iban?.replace(/\s/g, "").toUpperCase() || own);
    if (identities.some((id) => !id) || new Set(identities).size !== 1 || new Set(files.map(({ file }) => file.account?.currency ?? "EUR")).size !== 1) return accounts();
    const payments = /* @__PURE__ */ new Map();
    for (const { file } of files) for (const txn of file.transactions) {
      const previous = payments.get(txn.externalId);
      if (previous) {
        const balances2 = previous.balance !== void 0 && txn.balance !== void 0 && previous.balance !== txn.balance;
        if (previous.bookingDate !== txn.bookingDate || previous.amount !== txn.amount || previous.currency !== txn.currency || previous.description !== txn.description || previous.counterparty !== txn.counterparty || balances2) {
          throw new BankFileError("unknown", "Two statements give different payments with the same id. Import the statements separately and check them.");
        }
      } else payments.set(txn.externalId, txn);
    }
    return {
      ...files[0].file,
      transactions: [...payments.values()].sort((a, b) => a.bookingDate.localeCompare(b.bookingDate)),
      skipped: files.reduce((n, { file }) => n + (file.skipped ?? 0), 0)
    };
  }

  // src/engine/readers/xlsx.ts
  var import_fast_xml_parser3 = __toESM(require_fxp(), 1);

  // src/engine/readers/bank-profiles.ts
  var GH = "https://github.com/";
  var BANK_PROFILES = [
    {
      id: "sparkasse-camt",
      bank: "Sparkasse",
      variant: "CSV-CAMT V2 / V8",
      sources: [
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/main/vorlagen/bank-csv/sparkasse-lzo-camt-v2.csv`,
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/main/vorlagen/bank-csv/sparkasse-lzo-camt-v8.csv`,
        `${GH}omarkohl/ofxstatement-sparkasse-freiburg/blob/HEAD/src/ofxstatement/plugins/germany_sparkasse_freiburg.py`,
        `${GH}barredterra/camt-to-erpnext`,
        `${GH}firefly-iii/import-configurations/blob/main/de/sparkasse/csv-camt52v8.json`
      ],
      separator: ";",
      match: [
        "Auftragskonto",
        "Buchungstag",
        "Valutadatum",
        "Buchungstext",
        "Verwendungszweck",
        "Kundenreferenz (End-to-End)",
        "Beguenstigter/Zahlungspflichtiger",
        "Kontonummer/IBAN",
        "Betrag",
        "Info"
      ],
      dateFormat: ["DD.MM.YY", "DD.MM.YYYY"],
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Valutadatum",
        amount: "Betrag",
        counterparty: ["Beguenstigter/Zahlungspflichtiger"],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        iban: "Kontonummer/IBAN",
        accountIban: "Auftragskonto",
        currency: "Waehrung",
        status: "Info"
      },
      skipStatus: ["vorgemerkt"]
    },
    {
      id: "sparkasse-mt940",
      bank: "Sparkasse",
      variant: "CSV-MT940",
      sources: [
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/main/vorlagen/bank-csv/sparkasse-lzo-mt940.csv`,
        `${GH}firefly-iii/import-configurations/blob/main/de/sparkasse/neubrandenburg-demmin/csv-mt940.json`,
        `${GH}pretix/pretix/blob/master/src/tests/plugins/banktransfer/csvimport_data_de_sparkassernn.csv`
      ],
      unconfirmed: "An older variant (2015) wrote the booking day without its year (09.03); such rows are skipped.",
      separator: ";",
      match: [
        "Auftragskonto",
        "Buchungstag",
        "Valutadatum",
        "Buchungstext",
        "Verwendungszweck",
        "Beguenstigter/Zahlungspflichtiger",
        "Kontonummer",
        "BLZ",
        "Betrag",
        "Info"
      ],
      dateFormat: ["DD.MM.YY", "DD.MM.YYYY"],
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Valutadatum",
        amount: "Betrag",
        counterparty: ["Beguenstigter/Zahlungspflichtiger"],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        iban: "Kontonummer",
        accountIban: "Auftragskonto",
        currency: "Waehrung",
        status: "Info"
      },
      skipStatus: ["vorgemerkt"]
    },
    {
      // The eleven Sparda-Banks run on the same platform (Atruvia) since their move, the last in October 2025, and
      // export this layout too, with their own name in "Bankname Auftragskonto" ("Sparda-Bank West eG").
      id: "volksbank",
      bank: "VR Bank",
      // Volksbanken and Raiffeisenbanken, named as the server names them
      variant: "Atruvia CSV, since 2022",
      sources: [
        `${GH}sercxanto/go-homebank-csv/blob/HEAD/pkg/parser/testfiles/volksbank/Umsaetze_DE12345678901234567890_2023.10.04.csv`,
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/main/vorlagen/bank-csv/vr-teilhaberbank.csv`,
        `${GH}Fjanks/beancount-importer-volksbank/blob/HEAD/beancount_importer_volksbank/__init__.py`,
        `${GH}firefly-iii/import-configurations/blob/main/de/raiffeisenbank/bonn-rhein-sieg/csv-giro.json`,
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/dd3db03ab5525a99651a09869754eba189286b42/vorlagen/bank-csv/sparda-bank-west.csv`,
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/dd3db03ab5525a99651a09869754eba189286b42/vorlagen/bank-csv/README.md`,
        "https://www.it-finanzmagazin.de/systemumstellung-abgeschlossen-sparda-bank-west-vollendet-migration-auf-atruvia-kernbankverfahren-234291/"
      ],
      unconfirmed: "Sparda-Banks: one bank's export is public (Sparda-Bank West, December 2025); the other ten are taken to export the same, on the same platform.",
      separator: ";",
      match: ["IBAN Auftragskonto", "Buchungstag", "Name Zahlungsbeteiligter", "Betrag"],
      bankInColumn: { column: "Bankname Auftragskonto", names: ["Sparda-Bank"] },
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Valutadatum",
        amount: "Betrag",
        sign: "Soll/Haben",
        counterparty: ["Name Zahlungsbeteiligter"],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        iban: "IBAN Zahlungsbeteiligter",
        accountIban: "IBAN Auftragskonto",
        balance: "Saldo nach Buchung",
        currency: ["Waehrung", "W\xE4hrung"]
      },
      reader: "vrbank"
    },
    {
      id: "volksbank-2021",
      bank: "VR Bank",
      // Volksbanken and Raiffeisenbanken, named as the server names them
      variant: "Fiducia CSV, 2021\u20132022",
      sources: [
        `${GH}Fjanks/beancount-importer-volksbank/blob/HEAD/beancount_importer_volksbank/__init__.py`,
        `${GH}sercxanto/small_scripts/commit/22fa8d5728b5bb0a538f840ade3ae87e4264c257`
      ],
      unconfirmed: "The lines above the table and the totals below it are taken from the sources' description, not a file.",
      separator: ";",
      match: ["Buchungstag", "Valuta", "Textschl\xFCssel", "Primanota", "Zahlungsempf\xE4nger", "Vorgang/Verwendungszweck", "Umsatz", "Soll/Haben"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Valuta",
        amount: "Umsatz",
        sign: "Soll/Haben",
        counterparty: ["Zahlungsempf\xE4nger"],
        text: ["Vorgang/Verwendungszweck"],
        iban: "Zahlungsempf\xE4ngerIBAN",
        currency: "W\xE4hrung",
        status: "Kundenreferenz"
      },
      skipStatus: ["anfangssaldo", "endsaldo"]
      // the opening and closing balance lines below the table
    },
    {
      id: "volksbank-classic",
      bank: "VR Bank",
      // Volksbanken and Raiffeisenbanken, named as the server names them
      variant: "Fiducia CSV, until 2021",
      sources: [
        `${GH}leolabs/you-need-a-parser/blob/HEAD/packages/ynap-parsers/src/de/volksbank-eg/test-data/Umsaetze_test_2019.06.19.csv`,
        `${GH}Fjanks/beancount-importer-volksbank/blob/HEAD/beancount_importer_volksbank/__init__.py`,
        `${GH}bank2ynab/bank2ynab/blob/master/bank2ynab.conf`
      ],
      separator: ";",
      match: ["Buchungstag", "Valuta", "Auftraggeber/Zahlungsempf\xE4nger", "Empf\xE4nger/Zahlungspflichtiger", "Vorgang/Verwendungszweck", "Umsatz"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Valuta",
        amount: "Umsatz",
        sign: 12,
        // the S/H column has a blank name
        counterparty: ["Empf\xE4nger/Zahlungspflichtiger"],
        text: ["Vorgang/Verwendungszweck"],
        iban: "IBAN",
        currency: "W\xE4hrung",
        status: "Kundenreferenz"
      },
      skipStatus: ["anfangssaldo", "endsaldo"]
    },
    {
      id: "ing",
      bank: "ING",
      variant: "Umsatzanzeige",
      sources: [
        `${GH}nicolasmg-pr/FinAnt/blob/HEAD/docs/import-formats.md`,
        `${GH}twiederk/finance/blob/HEAD/src/test/resources/Umsatzanzeige_02_rows.csv`,
        `${GH}leolabs/you-need-a-parser/blob/HEAD/packages/ynap-parsers/src/de/ing-diba/test-data/Umsatzanzeige_DE00000105170000890000_20190403.csv`,
        `${GH}siddhantgoel/beancount-ing/blob/main/beancount_ing/ec.py`,
        `${GH}firefly-iii/import-configurations/blob/main/de/ing/Readme.md`
      ],
      unconfirmed: 'The "Referenz" column (new in 2026) is not used as an id: no source says it is unique.',
      separator: ";",
      match: ["Buchung", "Auftraggeber/Empf\xE4nger", "Buchungstext", "Verwendungszweck", "Betrag"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchung",
        valueDate: ["Wertstellungsdatum", "Valuta"],
        amount: "Betrag",
        counterparty: ["Auftraggeber/Empf\xE4nger"],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        balance: "Saldo",
        currency: ["W\xE4hrung (2)", "W\xE4hrung"]
        // with a balance, the first "Währung" is the balance's
      }
    },
    {
      id: "dkb",
      bank: "DKB",
      variant: "Girokonto, since 2023",
      sources: [
        `${GH}siddhantgoel/beancount-dkb/issues/123`,
        `${GH}siddhantgoel/beancount-dkb/issues/146`,
        `${GH}siddhantgoel/beancount-dkb/issues/206`,
        `${GH}milenvoutchev/2ynab/blob/HEAD/samples/DkbGirokonto2026.csv`,
        `${GH}d-led/auto-ynab-csv/blob/HEAD/data/samples/dkb-giro.csv`
      ],
      separator: [";", ","],
      // comma-separated for a while in late 2024
      match: ["Buchungsdatum", "Wertstellung", "Status", "Zahlungspflichtige*r", "Zahlungsempf\xE4nger*in", "Verwendungszweck", "Umsatztyp"],
      dateFormat: ["DD.MM.YY", "DD.MM.YYYY"],
      numberFormat: "de",
      columns: {
        date: "Buchungsdatum",
        valueDate: "Wertstellung",
        amount: ["Betrag (\u20AC)", "Betrag"],
        payer: "Zahlungspflichtige*r",
        payee: "Zahlungsempf\xE4nger*in",
        text: ["Verwendungszweck"],
        iban: "IBAN",
        status: "Status"
      },
      skipStatus: ["vorgemerkt"]
    },
    {
      id: "dkb-old",
      bank: "DKB",
      variant: "Girokonto, until 2023",
      sources: [
        `${GH}siddhantgoel/beancount-dkb/issues/123`,
        `${GH}siddhantgoel/beancount-dkb/blob/main/beancount_dkb/extractors/ec.py`,
        `${GH}firefly-iii/import-configurations/blob/main/de/dkb/README.md`
      ],
      separator: ";",
      match: ["Buchungstag", "Wertstellung", "Buchungstext", "Auftraggeber / Beg\xFCnstigter", "Verwendungszweck", "Kontonummer", "BLZ", "Betrag (EUR)"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Wertstellung",
        amount: "Betrag (EUR)",
        counterparty: ["Auftraggeber / Beg\xFCnstigter"],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        iban: "Kontonummer",
        status: "Buchungstext"
      },
      skipStatus: ["tagessaldo"]
      // balance lines, not payments
    },
    {
      id: "dkb-visa",
      bank: "DKB Visa",
      variant: "Kreditkarte, since 2023",
      sources: [
        `${GH}siddhantgoel/beancount-dkb/issues/163`,
        `${GH}siddhantgoel/beancount-dkb/issues/190`,
        `${GH}siddhantgoel/beancount-dkb/issues/206`
      ],
      unconfirmed: "Date format and the sign of purchases are taken to be as in DKB's Girokonto export (no source states them).",
      separator: [";", ","],
      match: ["Belegdatum", "Wertstellung", "Status", "Beschreibung", "Umsatztyp", ["Betrag (\u20AC)", "Betrag"]],
      dateFormat: ["DD.MM.YY", "DD.MM.YYYY"],
      numberFormat: "de",
      columns: {
        date: "Belegdatum",
        valueDate: "Wertstellung",
        amount: ["Betrag (\u20AC)", "Betrag"],
        counterparty: ["Beschreibung"],
        status: "Status"
      },
      skipStatus: ["vorgemerkt"]
    },
    {
      id: "dkb-visa-old",
      bank: "DKB Visa",
      variant: "Kreditkarte, until 2023",
      sources: [
        `${GH}siddhantgoel/beancount-dkb/issues/123`,
        `${GH}siddhantgoel/beancount-dkb/blob/main/beancount_dkb/extractors/credit.py`
      ],
      separator: ";",
      match: ["Umsatz abgerechnet und nicht im Saldo enthalten", "Wertstellung", "Belegdatum", "Beschreibung", "Betrag (EUR)"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: { date: "Belegdatum", valueDate: "Wertstellung", amount: "Betrag (EUR)", counterparty: ["Beschreibung"] }
    },
    {
      id: "comdirect",
      bank: "comdirect",
      variant: "Girokonto",
      sources: [
        `${GH}leolabs/you-need-a-parser/blob/HEAD/packages/ynap-parsers/src/de/comdirect/test-data/umsaetze_1182395341_20190403-2324.csv`,
        `${GH}leolabs/you-need-a-parser/blob/HEAD/packages/ynap-parsers/src/de/comdirect/comdirect.ts`,
        `${GH}pb-/beancount-comdirect/blob/HEAD/beancount_comdirect/accounts.py`,
        `${GH}sercxanto/go-homebank-csv/blob/HEAD/pkg/parser/testfiles/comdirect/umsaetze_1234567890_20231006_1804.csv`
      ],
      unconfirmed: "A file with several account sections is refused; BankFile can represent only one account.",
      separator: ";",
      match: ["Buchungstag", "Wertstellung (Valuta)", "Vorgang", "Buchungstext", "Umsatz in EUR"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: { date: "Buchungstag", valueDate: "Wertstellung (Valuta)", amount: "Umsatz in EUR", text: ["Buchungstext"], kind: "Vorgang" },
      labelledText: {
        labels: ["Auftraggeber", "Empf\xE4nger", "Zahlungspflichtiger", "Kto/IBAN", "BLZ/BIC", "Buchungstext", "Ref"],
        counterparty: ["Empf\xE4nger", "Zahlungspflichtiger", "Auftraggeber"],
        text: ["Buchungstext"]
      }
    },
    {
      id: "comdirect-visa",
      bank: "comdirect Visa",
      variant: "Kreditkarte",
      sources: [
        `${GH}pb-/beancount-comdirect/blob/HEAD/tests/test_multi_importer.py`,
        `${GH}APACGAMONDE/APACGAMONDE-Bank-Public/blob/HEAD/SCSV_Test_2019-08-28_17-14-39-480.csv`
      ],
      unconfirmed: "The newest public example of this section is from 2019\u20132021.",
      separator: ";",
      match: ["Buchungstag", "Umsatztag", "Vorgang", "Referenz", "Buchungstext", "Umsatz in EUR"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: { date: "Umsatztag", valueDate: "Buchungstag", amount: "Umsatz in EUR", counterparty: ["Buchungstext"], status: "Buchungstag" },
      skipStatus: ["offen"]
    },
    {
      id: "commerzbank",
      bank: "Commerzbank",
      sources: [
        `${GH}tireminnanzi/HomeExp/blob/92f4f33a87863e7a15007d2b20feb4de23f1a45c/doc%20banca/202404_202505_CMZB.csv`,
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/cd2a4903031349c3f4c667f993ff6b22956d6f82/vorlagen/bank-csv/commerzbank.csv`,
        `${GH}siddhantgoel/beancount-commerzbank/blob/604772fcb4e7dc26cf0382990622247cba758e7d/beancount_commerzbank/ec.py`,
        `${GH}firefly-iii/import-configurations/blob/cea1aa12a6ff5332b5f69a51f409eba5cd4b5135/de/commerzbank/csv-giro.json`,
        `${GH}bank2ynab/bank2ynab/blob/9f3b3e89ea3d559d6c8e132d21d59659d45b7e82/test/test-data/Umsaetze_KtoNr538917600_EUR_02-03-2018_1503.CSV`
      ],
      unconfirmed: "The counterparty has no column of its own; it stays inside the text, which ends where the references start.",
      separator: ";",
      match: ["Buchungstag", "Wertstellung", "Umsatzart", "Buchungstext", "Betrag", "W\xE4hrung"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Wertstellung",
        amount: "Betrag",
        text: ["Buchungstext"],
        kind: "Umsatzart",
        currency: "W\xE4hrung",
        accountIban: ["IBAN Kontoinhaber", "IBAN Auftraggeberkonto"]
        // the account's own IBAN
      },
      labelledText: { labels: ["End-to-End-Ref", "Mandatsref", "Gl\xE4ubiger-ID"], counterparty: [], text: [""] }
    },
    {
      id: "deutsche-bank",
      bank: "Deutsche Bank",
      variant: "since 2023 at Postbank, 2025 at Deutsche Bank",
      sources: [
        `${GH}firefly-iii/import-configurations/blob/cea1aa12a6ff5332b5f69a51f409eba5cd4b5135/de/deutschebank/Readme.md`,
        `${GH}TMosebach/slowen/blob/62ef0cea419bed876f7b309f5914e843cba97871/test/dtbank-importtest-monat1.csv`,
        `${GH}RtCryo/cash-cockpit/blob/4e9288ac6a2c77ab55a631ae5f90dcff9aaf683b/handler/src/test/resources/Kontoumsaetze_367_6139117_00_20231218_105036.csv`,
        `${GH}eschmidt42/fintl/blob/3eb14d22b221b7d15726756b975e52407ef15385/tests/files/csv_files/Postbank/Kontoumsaetze_123_1234567_12_20231028_083011.csv`,
        `${GH}BananaAccounting/Germany/blob/ff42561a7dbe2a70a7791bb9aba993eebdb48b98/importApps/deutschepostbank_import_bank_statement_csv/test/testcases/csv_deutschepostbank_example_format1_20250414.csv`
      ],
      separator: ";",
      match: ["Buchungstag", "Wert", "Umsatzart", "Beg\xFCnstigter / Auftraggeber", "Verwendungszweck", "IBAN / Kontonummer", "Betrag", "Soll", "Haben"],
      bankInPreamble: ["Postbank", "Deutsche Bank"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Wert",
        amount: "Betrag",
        counterparty: ["Beg\xFCnstigter / Auftraggeber"],
        text: ["Verwendungszweck"],
        kind: "Umsatzart",
        iban: "IBAN / Kontonummer",
        currency: "W\xE4hrung"
      }
    },
    {
      id: "deutsche-bank-old",
      bank: "Deutsche Bank",
      variant: "until 2025",
      sources: [
        `${GH}BananaAccounting/Germany/blob/ff42561a7dbe2a70a7791bb9aba993eebdb48b98/importApps/deutschebank_import_bank_statement_csv/test/testcases/csv_deutschebank_example_format3_20240131.csv`,
        `${GH}BananaAccounting/Germany/blob/ff42561a7dbe2a70a7791bb9aba993eebdb48b98/importApps/deutschebank_import_bank_statement_csv/ch.banana.germany.import.deutschebank.js`,
        `${GH}firefly-iii/import-configurations/commit/6dae608005f27e4fdc249c3cece537736610bcbc`
      ],
      separator: ";",
      match: ["Buchungstag", "Wert", "Umsatzart", "Beg\xFCnstigter / Auftraggeber", "Verwendungszweck", "IBAN", "Soll", "Haben"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungstag",
        valueDate: "Wert",
        debit: "Soll",
        credit: "Haben",
        counterparty: ["Beg\xFCnstigter / Auftraggeber"],
        text: ["Verwendungszweck"],
        kind: "Umsatzart",
        iban: "IBAN",
        currency: "W\xE4hrung"
      }
    },
    {
      id: "deutsche-bank-old-en",
      bank: "Deutsche Bank",
      variant: "until 2025, English",
      sources: [
        `${GH}mshogin/tx2ledger/blob/c5ff013a410c10e0a6a0e73f9bebe6553f3f1e68/testdata/tx.csv`,
        `${GH}mafflin/moritz/blob/1d3e85210fa677e24cc20c50785b961403a16466/spec/fixtures/files/db.csv`,
        `${GH}bank2ynab/bank2ynab/blob/9f3b3e89ea3d559d6c8e132d21d59659d45b7e82/bank2ynab/data/bank2ynab.conf`
      ],
      separator: ";",
      match: ["Booking date", "Value date", "Transaction Type", "Beneficiary / Originator", "Payment Details", "Debit", "Credit"],
      dateFormat: "MM/DD/YYYY",
      numberFormat: "en",
      columns: {
        date: "Booking date",
        valueDate: "Value date",
        debit: "Debit",
        credit: "Credit",
        counterparty: ["Beneficiary / Originator"],
        text: ["Payment Details"],
        kind: "Transaction Type",
        iban: "IBAN",
        currency: "Currency"
      }
    },
    {
      id: "postbank-old",
      bank: "Postbank",
      variant: "Umsatzauskunft, until 2023",
      sources: [
        `${GH}eschmidt42/fintl/blob/3eb14d22b221b7d15726756b975e52407ef15385/tests/files/csv_files/Postbank/Umsatzauskunft_KtoNr0123456789_31-12-2021_17-20-43.csv`,
        `${GH}Corion/Finance-Bank-Postbank_de/blob/70acd3311f203dd4c3a8c3f4e66f51226b715afc/t/accountstatement.txt`
      ],
      separator: ";",
      // The booked table (the upcoming payments above it have no value date and no balance column).
      match: ["Buchungsdatum", "Wertstellung", "Umsatzart", "Buchungsdetails", "Auftraggeber", "Empf\xE4nger", "Betrag (\u20AC)", "Saldo (\u20AC)"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungsdatum",
        valueDate: "Wertstellung",
        amount: "Betrag (\u20AC)",
        payer: "Auftraggeber",
        payee: "Empf\xE4nger",
        text: ["Buchungsdetails"],
        kind: "Umsatzart",
        balance: "Saldo (\u20AC)"
      }
    },
    {
      id: "n26",
      bank: "N26",
      variant: "since 2023",
      sources: [
        `${GH}leolabs/you-need-a-parser/issues/661`,
        `${GH}siddhantgoel/beancount-n26/blob/e53796b58805f8396be4002ac373e0e89f613c58/CHANGELOG.md`
      ],
      unconfirmed: "No German-language header of this layout was found.",
      separator: ",",
      match: ["Booking Date", "Value Date", "Partner Name", "Partner Iban", "Type", "Payment Reference", "Amount (EUR)"],
      dateFormat: "YYYY-MM-DD",
      numberFormat: "en",
      columns: {
        date: "Booking Date",
        valueDate: "Value Date",
        amount: "Amount (EUR)",
        counterparty: ["Partner Name"],
        iban: "Partner Iban",
        text: ["Payment Reference"]
      }
    },
    {
      id: "n26-old",
      bank: "N26",
      variant: "until 2023",
      sources: [
        `${GH}leolabs/you-need-a-parser/blob/cacad521a503c0b905bd350cffe4a6dec6930ee7/packages/ynap-parsers/src/de/n26/test-data/n26-csv-transactions-2021.csv`,
        `${GH}siddhantgoel/beancount-n26/blob/e53796b58805f8396be4002ac373e0e89f613c58/beancount_n26/__init__.py`,
        `${GH}simonmichael/hledger/blob/6833d59b175974f9d15ecf3f87d134347df9ae3d/examples/csv/banking/n26-main.rules`,
        `${GH}firefly-iii/import-configurations/blob/cea1aa12a6ff5332b5f69a51f409eba5cd4b5135/de/n26/default.json`
      ],
      unconfirmed: "The German header's date and number format are not shown in a file; both forms are accepted.",
      separator: ",",
      match: [
        ["Date", "Datum"],
        ["Payee", "Empf\xE4nger"],
        ["Account number", "Kontonummer"],
        ["Transaction type", "Transaktionstyp"],
        ["Payment reference", "Verwendungszweck"],
        ["Amount (EUR)", "Betrag (EUR)"]
      ],
      dateFormat: ["YYYY-MM-DD", "DD.MM.YYYY"],
      numberFormat: "either",
      columns: {
        date: ["Date", "Datum"],
        amount: ["Amount (EUR)", "Betrag (EUR)"],
        counterparty: [["Payee", "Empf\xE4nger"]],
        iban: ["Account number", "Kontonummer"],
        text: [["Payment reference", "Verwendungszweck"]]
      }
    },
    {
      id: "revolut",
      bank: "Revolut",
      sources: [
        `${GH}mlaitinen/ofxstatement-revolut/tree/c3a3826cc472befd7d1413be10628302d667b314`,
        `${GH}BananaAccounting/Universal/tree/c231b374a7c9c7d8a6cda33262487d228b45b238/extensions/import/revolut`,
        `${GH}kelvan/money_parser_rs/blob/31343cbc104ff50e947c924f056af96b5c959fd8/src/locale/revolut.rs`,
        `${GH}martinzoeller/revolut-grab-exporter/blob/3c172232391bdaaca8fd83e9fdc72d5c14d31036/internal/infrastructure/csv/reader.go`
      ],
      unconfirmed: "German status words other than ABGESCHLOSSEN were not found; only completed rows are read.",
      separator: ",",
      match: [
        ["Type", "Art"],
        ["Product", "Produkt"],
        ["Started Date", "Datum des Beginns"],
        ["Completed Date", "Datum des Abschlusses"],
        ["Description", "Beschreibung"],
        ["Amount", "Betrag"],
        ["State", "Status"]
      ],
      dateFormat: "YYYY-MM-DD",
      numberFormat: "en",
      columns: {
        date: ["Started Date", "Datum des Beginns"],
        valueDate: ["Completed Date", "Datum des Abschlusses"],
        amount: ["Amount", "Betrag"],
        fees: [["Fee", "Geb\xFChr"]],
        counterparty: [["Description", "Beschreibung"]],
        balance: ["Balance", "Kontostand"],
        currency: ["Currency", "W\xE4hrung"],
        status: ["State", "Status"]
      },
      keepStatus: ["completed", "abgeschlossen"]
      // pending, reverted and declined rows moved no money (yet)
    },
    {
      id: "trade-republic",
      bank: "Trade Republic",
      variant: "Transaktionsexport, since 2026",
      sources: [
        `${GH}portfolio-performance/portfolio/blob/2a0ef52a93882c0845596b2c6b834e54f592b7ec/name.abuchen.portfolio/src/name/abuchen/portfolio/datatransfer/traderepublic/TradeRepublicCSVExtractor.java`,
        `${GH}portfolio-performance/portfolio/tree/2a0ef52a93882c0845596b2c6b834e54f592b7ec/name.abuchen.portfolio.tests/src/name/abuchen/portfolio/datatransfer/traderepublic`,
        `${GH}VibeNL/GhostfolioSidekick/tree/f894bcdbcd96541353b74daa8edd689cfc7900d5/Parsers.UnitTests/TestFiles/TradeRepublic/CSV`
      ],
      unconfirmed: "Which of the two variants (comma or semicolon) is current; no German column names were found.",
      separator: [",", ";"],
      match: ["datetime", "date", "category", "type", "amount", "currency", "transaction_id"],
      dateFormat: "YYYY-MM-DD",
      numberFormat: "en",
      columns: {
        date: "date",
        valueDate: "value_date",
        amount: "amount",
        addAmounts: ["fee", "tax"],
        counterparty: ["counterparty_name", "name"],
        iban: "counterparty_iban",
        text: ["payment_reference", "description"],
        currency: "currency",
        reference: "transaction_id"
      }
    },
    {
      id: "consorsbank",
      bank: "Consorsbank",
      sources: [
        `${GH}Ralphovi/ofxstatement-consorsbank/tree/c7daaf4e8591e07860f1670d0ba1ed8029e8cb73`,
        `${GH}aniav/ynab-csv/issues/1#issuecomment-369678842`,
        `${GH}bank2ynab/bank2ynab/issues/241`
      ],
      unconfirmed: "The 2025\u20132026 layout comes from an importer's test file built on real exports, not from a raw export.",
      separator: ";",
      match: [
        "Buchung",
        "Valuta",
        "Sender / Empf\xE4nger",
        ["IBAN", "IBAN / Konto-Nr."],
        "Buchungstext",
        "Verwendungszweck",
        ["Betrag", "Betrag in EUR"]
      ],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchung",
        valueDate: "Valuta",
        amount: ["Betrag", "Betrag in EUR"],
        counterparty: ["Sender / Empf\xE4nger"],
        iban: ["IBAN", "IBAN / Konto-Nr."],
        text: ["Verwendungszweck"],
        kind: "Buchungstext",
        currency: "W\xE4hrung"
      }
    },
    {
      id: "c24",
      bank: "C24",
      variant: "Smartkonto",
      sources: [
        `${GH}anydef/finreport/blob/bb6aea2c1d14731880d37e94b69d331021b99da8/finreport-rs/c24-csv/src/parser.rs`,
        `${GH}fer0n/Relay/blob/601c317a2bac55afabf8db6493e3715b30f5dd6e/RelayTests/StatementImportParsingTests.swift`,
        `${GH}13excite/c24-expences/blob/d18a48a0fda8451c95e5f3b29fd2819da675518a/testdata/transaction.csv.mock`
      ],
      unconfirmed: 'Several C24 accounts ("Kontoname") in one file are refused. Pending rows: unknown.',
      separator: ",",
      match: ["Transaktionstyp", "Buchungsdatum", "Betrag", "Zahlungsempf\xE4nger", "Verwendungszweck", "Beschreibung"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungsdatum",
        amount: "Betrag",
        counterparty: ["Zahlungsempf\xE4nger"],
        iban: "IBAN",
        text: ["Verwendungszweck", "Beschreibung"],
        kind: "Transaktionstyp"
      }
    },
    {
      id: "amex",
      bank: "American Express",
      sources: [
        `${GH}Viniciussteigleder/CoupleFin/blob/77527b5982ba5b70b6358f74ce2e86f631a20f30/Sample_transaction_import/CSV/Amex/activity%20(8).csv`,
        `${GH}adrianlemess/AMEX-UI/blob/0f99dcac47f916871a9e18f8fb80e1e07f77b8ff/apps/api/src/amex/activity.test.ts`,
        `${GH}Galaxy102/openbank-transactions-to-hibiscus/blob/a1c79ef55b38e991a06588267c2a00cb79ead0ca/loaders/amex.py`,
        "https://help.lexware.de/de-form/articles/548879-lexware-office-american-express-als-konto-ohne-verbindung-fuhren"
      ],
      unconfirmed: "How pending rows look, and the header of the English-language site.",
      separator: ",",
      match: ["Datum", "Beschreibung", "Karteninhaber", "Konto #", "Betrag", "Betreff"],
      dateFormat: "DD/MM/YYYY",
      numberFormat: "de",
      columns: { date: "Datum", amount: "Betrag", counterparty: ["Beschreibung"], reference: "Betreff" },
      invertSign: true
      // purchases are positive, payments to the card negative
    },
    {
      id: "targobank",
      bank: "Targobank",
      variant: "Girokonto",
      sources: [
        `${GH}nicolettas-muggelbude/RechnungsFee/blob/cd2a4903031349c3f4c667f993ff6b22956d6f82/vorlagen/bank-csv/targobank-duesseldorf.csv`,
        `${GH}replikativ/kontor/blob/78c94812a63700f048306493d0ecf183a3919f54/modules/bank-de/test/resources/targobank-duesseldorf.csv`,
        `${GH}Notausstieg0309/MoneyWatch/blob/200101565c93e35ff8a72df8cf3d7a933b2024e4/src/moneywatch/import_plugins/targobank.py`
      ],
      unconfirmed: "No header row: recognised by its seven columns with the account's IBAN last. Counterparty, IBAN and text share one column.",
      separator: ";",
      match: [],
      headerless: { columnCount: 7, ibanColumn: 6 },
      dateFormat: "DD.MM.YYYY",
      numberFormat: "either",
      // the same account has exported both -5,00 and -5.00
      columns: { date: 0, text: [1], debit: 2, credit: 3, accountIban: 6 }
    },
    {
      id: "barclays",
      bank: "Barclays",
      variant: "Excel export saved as CSV",
      sources: [
        `${GH}firefly-iii/import-configurations/blob/main/de/barclays/Readme.md`,
        `${GH}firefly-iii/import-configurations/blob/main/de/barclays/barclays.json`,
        `${GH}phdorp/firefly-cash-converter/blob/9a0a940f55f512a89da1ec27a368ecae4fbbcf7d/test/data/barclays.xlsx`,
        `${GH}sercxanto/go-homebank-csv/blob/5c20f3ed964ceca073fa832f54406703729399ae/pkg/parser/barclaycard.go`
      ],
      unconfirmed: 'Barclays (now easybank) offers no CSV, only Excel (.xlsx), which the app cannot read; this reads the Excel file saved as CSV. Which of the two "Buchungsdatum" columns is the purchase day: sources disagree (here the first).',
      separator: [";", ","],
      match: ["Referenznummer", "Buchungsdatum", "Betrag", "Beschreibung", "Typ", "Status", "Kartennummer"],
      dateFormat: "DD.MM.YYYY",
      numberFormat: "de",
      columns: {
        date: "Buchungsdatum",
        valueDate: "Buchungsdatum (2)",
        amount: "Betrag",
        counterparty: ["Beschreibung"],
        text: [["Details", "H\xE4ndlerdetails"]],
        kind: "Typ",
        reference: "Referenznummer",
        status: "Status"
      },
      skipStatus: ["vorgemerkt"]
    }
  ];

  // src/engine/readers/profiles.ts
  var formats = (profile) => Array.isArray(profile.dateFormat) ? profile.dateFormat : [profile.dateFormat];
  var names = (column) => Array.isArray(column) ? column : [column];
  function fitsHeaderless(profile, rows) {
    const shape = profile.headerless;
    const first = rows.find((r) => r.some((v) => v.trim() !== ""));
    if (!first || first.length !== shape.columnCount || typeof profile.columns.date !== "number") return false;
    if (!DATE_FORMATS.some((f) => parseDate(first[profile.columns.date] ?? "", f) !== null)) return false;
    return shape.ibanColumn === void 0 || normalizeIban(first[shape.ibanColumn] ?? "") !== null;
  }
  function findProfile(rows, _separator) {
    let best = null;
    for (const profile of BANK_PROFILES) {
      if (profile.headerless) {
        if (!best && fitsHeaderless(profile, rows)) best = { profile, headerRow: -1 };
        continue;
      }
      const headerRow = findHeaderRow(rows, profile.match.map((m) => (Array.isArray(m) ? m : [m]).map(headerKey)));
      if (headerRow < 0) continue;
      if (!best || best.headerRow < 0 || headerRow < best.headerRow || headerRow === best.headerRow && profile.match.length > best.profile.match.length) best = { profile, headerRow };
    }
    return best;
  }
  function fileNumberFormat(rows, columns, preferred = "de") {
    let de = 0, en = 0;
    for (const row of rows) for (const j of columns) {
      const v = row[j] ?? "";
      if (parseAmountStrict(v, "de") !== null) de++;
      if (parseAmountStrict(v, "en") !== null) en++;
    }
    return en === de ? preferred : en > de ? "en" : "de";
  }
  function profileDateAmbiguous(profile, rows, headerRow, layout2) {
    if (formats(profile).includes(layout2.dateFormat)) return false;
    const choices = columnDateFormats(rows.slice(headerRow + 1).map((r) => r[layout2.columns.date] ?? ""));
    return choices.includes("DD/MM/YYYY") && choices.includes("MM/DD/YYYY");
  }
  function fileBank(profile, rows, headerRow) {
    const above = rows.slice(0, Math.max(headerRow, 0)).map((r) => r.join(" ").toLowerCase());
    const inPreamble = profile.bankInPreamble?.find((n) => above.some((line) => line.includes(n.toLowerCase())));
    if (inPreamble) return inPreamble;
    const named = profile.bankInColumn;
    if (named && headerRow >= 0) {
      const column = rows[headerRow].findIndex((h) => headerKey(h) === headerKey(named.column));
      const cells = column < 0 ? [] : rows.slice(headerRow + 1).map((r) => (r[column] ?? "").toLowerCase());
      const inColumn = named.names.find((n) => cells.some((cell2) => cell2.includes(n.toLowerCase())));
      if (inColumn) return inColumn;
    }
    return profile.bank;
  }
  function profileLayout(profile, rows, headerRow, separator) {
    const header = headerRow >= 0 ? trimRow(rows[headerRow]) : [];
    const keys = uniqueHeader(headerRow >= 0 ? rows[headerRow].map((h) => h.trim()) : []).map(headerKey);
    const at = (column) => {
      for (const name of column === void 0 ? [] : names(column)) {
        if (typeof name === "number") return name;
        const i2 = keys.indexOf(headerKey(name));
        if (i2 >= 0) return i2;
      }
      return void 0;
    };
    const p = profile.columns;
    const columns = { date: at(p.date) ?? -1 };
    for (const role of [
      "valueDate",
      "amount",
      "debit",
      "credit",
      "sign",
      "payer",
      "payee",
      "kind",
      "iban",
      "accountIban",
      "balance",
      "currency",
      "reference",
      "status"
    ]) {
      const i2 = at(p[role]);
      if (i2 !== void 0) columns[role] = i2;
    }
    for (const role of ["counterparty", "text", "fees", "addAmounts"]) {
      const list2 = (p[role] ?? []).map(at).filter((i2) => i2 !== void 0);
      if (list2.length > 0) columns[role] = list2;
    }
    if (columns.date < 0) return null;
    if (columns.amount === void 0 && (columns.debit === void 0 || columns.credit === void 0)) return null;
    const amountColumns = [columns.amount, columns.debit, columns.credit].filter((i2) => i2 !== void 0);
    const data = rows.slice(headerRow + 1).filter((r) => r.some((v) => v.trim() !== ""));
    const dateFormat2 = columnDateFormats(data.map((r) => r[columns.date] ?? ""), formats(profile))[0] ?? formats(profile)[0];
    return {
      version: 1,
      name: fileBank(profile, rows, headerRow),
      profile: profile.id,
      separator,
      header,
      ...profile.headerless ? { columnCount: profile.headerless.columnCount } : {},
      dateFormat: dateFormat2,
      numberFormat: fileNumberFormat(data, amountColumns, profile.numberFormat === "either" ? "de" : profile.numberFormat),
      columns,
      ...profile.skipStatus ? { skipStatus: profile.skipStatus } : {},
      ...profile.keepStatus ? { keepStatus: profile.keepStatus } : {},
      ...profile.invertSign ? { invertSign: true } : {},
      ...profile.currency ? { currency: profile.currency } : {},
      ...profile.labelledText ? { labelledText: profile.labelledText } : {}
    };
  }

  // src/engine/readers/xlsx.ts
  var fail2 = () => {
    throw new BankFileError("xlsx", "This Excel workbook could not be read. Export it as CSV or save a new .xlsx file.");
  };
  var XLSX_MAX_CELLS = 1e6;
  var XLSX_MAX_TEXT = 25 * 1024 * 1024;
  var textCost = (value) => value.length + 3 + (value.match(/"/g)?.length ?? 0);
  var parser2 = new import_fast_xml_parser3.XMLParser({
    ignoreAttributes: false,
    removeNSPrefix: true,
    parseTagValue: false,
    trimValues: false,
    processEntities: true
  });
  var arr2 = (x2) => x2 === void 0 ? [] : Array.isArray(x2) ? x2 : [x2];
  var text2 = (x2) => x2 == null ? "" : typeof x2 === "object" ? String(x2["#text"] ?? "") : String(x2);
  var rich = (x2) => x2 ? text2(x2.t) + arr2(x2.r).map((r) => text2(r.t)).join("") : "";
  function xml(files, path) {
    const bytes = files.get(path);
    if (!bytes) return fail2();
    const source = decodeBankFile(bytes);
    if (/<!DOCTYPE|<!ENTITY/i.test(source) || import_fast_xml_parser3.XMLValidator.validate(source) !== true) return fail2();
    try {
      return parser2.parse(source);
    } catch {
      return fail2();
    }
  }
  var isXlsx = (files) => files.has("[Content_Types].xml") && files.has("xl/workbook.xml");
  var rowsText = (rows) => rows.map((r) => r.map((v) => `"${v.replace(/"/g, '""')}"`).join(";")).join("\n");
  function excelDecimal(value, money2 = false) {
    const m = /^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(value.trim());
    if (!m) return fail2();
    const exponent = Number(m[4] ?? 0);
    if (!Number.isInteger(exponent) || Math.abs(exponent) > 1e3) return fail2();
    const digits = m[2] + (m[3] ?? ""), point = m[2].length + exponent;
    const whole = (point <= 0 ? "0" : digits.slice(0, point).padEnd(point, "0")).replace(/^0+(?=\d)/, "");
    let fraction = point < 0 ? "0".repeat(-point) + digits : digits.slice(point);
    fraction = fraction.replace(/0+$/, "");
    if (money2) fraction = fraction.padEnd(2, "0");
    return (m[1] === "-" && /[1-9]/.test(whole + fraction) ? "-" : "") + whole + (fraction ? "." + fraction : "");
  }
  var builtinDates = /* @__PURE__ */ new Set([14, 15, 16, 17, 22, 27, 28, 29, 30, 31, 34, 35, 36, 50, 51, 52, 53, 54, 55, 56, 57, 58]);
  function dateFormat(id, code) {
    const bare = code.replace(/"[^"]*"|\\.|\[[^\]]*\]/g, "");
    return builtinDates.has(id) || /y|d/i.test(bare);
  }
  function serialDate(value, mac) {
    const n = Number(excelDecimal(value));
    if (!Number.isFinite(n) || n < 0 || n > 2958465 || !mac && Math.floor(n) === 60) return fail2();
    const days = Math.floor(n);
    const ms = (mac ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 31)) + (days - (!mac && days > 60 ? 1 : 0)) * 864e5;
    return new Date(ms).toISOString().slice(0, 10);
  }
  function xlsxTableText(files, hasTable) {
    const workbook = xml(files, "xl/workbook.xml").workbook;
    if (!workbook) return fail2();
    const rels = arr2(xml(files, "xl/_rels/workbook.xml.rels").Relationships?.Relationship);
    const strings = files.has("xl/sharedStrings.xml") ? arr2(xml(files, "xl/sharedStrings.xml").sst?.si).map(rich) : [];
    const stringCosts = strings.map(textCost);
    const style = files.has("xl/styles.xml") ? xml(files, "xl/styles.xml").styleSheet : {};
    const formats2 = new Map(arr2(style?.numFmts?.numFmt).map((f) => [Number(f["@_numFmtId"]), String(f["@_formatCode"])]));
    const styles = arr2(style?.cellXfs?.xf).map((f) => ({ id: Number(f["@_numFmtId"] ?? 0), code: formats2.get(Number(f["@_numFmtId"])) ?? "" }));
    const mac = ["1", "true"].includes(String(workbook.workbookPr?.["@_date1904"]));
    for (const sheet of arr2(workbook.sheets?.sheet)) {
      const rel = rels.find((r) => r["@_Id"] === sheet["@_id"]);
      if (!rel || rel["@_TargetMode"] === "External" || !String(rel["@_Type"]).endsWith("/worksheet")) return fail2();
      const target = String(rel["@_Target"]);
      if (target.includes("..") || target.includes("\\")) return fail2();
      const path = target.startsWith("/") ? target.slice(1) : `xl/${target.replace(/^\.\//, "")}`;
      const data = xml(files, path).worksheet?.sheetData;
      const rows = [];
      const numeric = [];
      let width = 0, cells = 0, grid = 0, chars = 0;
      const spend = (n) => {
        chars += n;
        if (chars > XLSX_MAX_TEXT) fail2();
      };
      for (const row of arr2(data?.row)) {
        const values = [];
        for (const cell2 of arr2(row.c)) {
          if (++cells > 1e6) return fail2();
          const ref = /^([A-Z]+)(\d+)$/.exec(String(cell2["@_r"] ?? ""));
          if (cell2["@_r"] !== void 0 && !ref) return fail2();
          let col = values.length;
          if (ref) {
            col = 0;
            for (const c of ref[1]) col = col * 26 + c.charCodeAt(0) - 64;
            col--;
          }
          if (col >= 16384 || col < values.length) return fail2();
          const padding = col + 1 - values.length;
          grid += padding;
          if (grid > XLSX_MAX_CELLS) return fail2();
          spend(3 * padding);
          while (values.length <= col) values.push("");
          if (cell2.f !== void 0 || cell2["@_t"] === "e") return fail2();
          const value = text2(cell2.v), kind = cell2["@_t"];
          if (kind !== void 0 && !["s", "inlineStr", "b", "str", "d", "n"].includes(kind)) return fail2();
          const styleIndex = Number(cell2["@_s"] ?? 0);
          if (!Number.isInteger(styleIndex) || styleIndex < 0 || styleIndex > 0 && !styles[styleIndex]) return fail2();
          if (kind === "s") {
            if (!/^\d+$/.test(value) || strings[Number(value)] === void 0) return fail2();
            values[col] = strings[Number(value)];
            spend(stringCosts[Number(value)] - 3);
          } else if (kind === "inlineStr") values[col] = rich(cell2.is);
          else if (kind === "b") {
            if (value !== "0" && value !== "1") return fail2();
            values[col] = value === "1" ? "true" : "false";
          } else if (kind === "str" || kind === "d") values[col] = value;
          else if (value !== "") {
            const s = styles[styleIndex] ?? { id: 0, code: "" };
            if (dateFormat(s.id, s.code)) values[col] = serialDate(value, mac);
            else {
              const money2 = [2, 4, 7, 8, 39, 40, 43, 44].includes(s.id) || /[0#][.,]00|[$€£]/.test(s.code);
              values[col] = excelDecimal(value, money2);
              numeric.push({ row: rows.length, col, value, money: money2 });
            }
          }
          if (kind !== "s") spend(textCost(values[col]) - 3);
        }
        width = Math.max(width, values.length);
        rows.push(values);
      }
      if (rows.length * width > XLSX_MAX_CELLS) return fail2();
      spend(3 * (rows.length * width - grid));
      rows.forEach((r) => {
        while (r.length < width) r.push("");
      });
      const known = findProfile(rows);
      const layout2 = known ? profileLayout(known.profile, rows, known.headerRow, ";") : void 0;
      const moneyColumns = layout2 ? /* @__PURE__ */ new Set([
        layout2.columns.amount,
        layout2.columns.debit,
        layout2.columns.credit,
        layout2.columns.balance,
        ...layout2.columns.fees ?? [],
        ...layout2.columns.addAmounts ?? []
      ]) : /* @__PURE__ */ new Set();
      for (const c of numeric) if (c.money || moneyColumns.has(c.col)) rows[c.row][c.col] = excelDecimal(c.value, true);
      const table = rowsText(rows);
      if (hasTable(table)) return table;
    }
    throw new BankFileError("zip", "No bank payment table was found in this Excel workbook. Export a bank statement as CSV or .xlsx.");
  }

  // src/engine/readers/camt.ts
  var import_fast_xml_parser4 = __toESM(require_fxp(), 1);
  var parser3 = new import_fast_xml_parser4.XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    parseTagValue: false,
    // keep IBANs and amounts as strings
    removeNSPrefix: true
    // <ns2:Document> and friends
  });
  function arr3(x2) {
    if (x2 === void 0 || x2 === null) return [];
    return Array.isArray(x2) ? x2 : [x2];
  }
  function textOf2(node2) {
    if (node2 && typeof node2 === "object" && "#text" in node2) return String(node2["#text"]);
    return node2 == null || typeof node2 === "object" ? "" : String(node2);
  }
  var dateOnly = (value) => {
    const v = textOf2(value).trim();
    return /^\d{4}-\d{2}-\d{2}/.test(v) ? `${v.slice(0, 10)}T00:00:00.000Z` : null;
  };
  var nameOf = (party) => cleanText(textOf2(party?.Nm) || textOf2(party?.Pty?.Nm));
  var ibanOf = (account) => textOf2(account?.Id?.IBAN).replace(/\s/g, "");
  function entryCounterpartyIban(ntry) {
    if (!ntry || typeof ntry !== "object") return void 0;
    const node2 = ntry;
    const tx = arr3(node2.NtryDtls).flatMap((d) => arr3(d?.TxDtls))[0];
    const parties = tx?.RltdPties ?? {};
    return normalizeIban(ibanOf(node2.CdtDbtInd === "DBIT" ? parties.CdtrAcct : parties.DbtrAcct)) ?? void 0;
  }
  var remittance = (tx) => cleanText(...arr3(tx?.RmtInf?.Ustrd).map(textOf2)) || cleanText(...arr3(tx?.RmtInf?.Strd).map((s) => textOf2(s?.CdtrRefInf?.Ref))) || cleanText(textOf2(tx?.AddtlTxInf));
  function batchText(texts2) {
    const distinct = [...new Set(texts2.filter(Boolean))];
    return distinct.length > 3 ? `${distinct.slice(0, 3).join(" / ")} / \u2026` : distinct.join(" / ");
  }
  function signedAmount(node2) {
    const amount2 = parseAmountStrict(textOf2(node2.Amt), "en");
    if (!amount2) return null;
    return node2.CdtDbtInd === "DBIT" ? negate(amount2) : amount2;
  }
  function vrCamtId(ntry) {
    const isDebit = ntry.CdtDbtInd === "DBIT";
    const amount2 = `${isDebit ? "-" : ""}${parseAmount(textOf2(ntry.Amt))}`;
    const bookingDate2 = new Date(ntry.BookgDt?.Dt || ntry.BookgDt?.DtTm || ntry.ValDt?.Dt);
    const tx = arr3(ntry.NtryDtls?.TxDtls)[0];
    const remittance2 = arr3(tx?.RmtInf?.Ustrd).map(textOf2).join(" ").trim() || textOf2(ntry.AddtlNtryInf).trim() || "(no description)";
    const creditor = tx?.RltdPties?.Cdtr?.Nm;
    const debtor = tx?.RltdPties?.Dbtr?.Nm;
    const counterpartyRaw = (isDebit ? creditor : debtor) || creditor || debtor;
    const counterparty = counterpartyRaw ? String(counterpartyRaw) : null;
    const time = bookingDate2.getTime();
    const fields2 = `${isNaN(time) ? "Invalid Date" : bookingDate2.toISOString()}|${amount2}|${remittance2}|${counterparty ?? ""}`;
    const ref = ntry.AcctSvcrRef || tx?.Refs?.AcctSvcrRef || tx?.Refs?.EndToEndId || tx?.Refs?.TxId;
    return { id: ref && ref !== "NOTPROVIDED" ? String(ref) : hashId(fields2), fields: fields2 };
  }
  function isVrBank(iban, bic) {
    if (!iban && !bic) return true;
    if (bic.toUpperCase().startsWith("GENO")) return true;
    return /^DE\d{2}\d{3}[69]/.test(iban);
  }
  var PENDING = /* @__PURE__ */ new Set(["PDNG", "INFO", "FUTR"]);
  var statusOf = (ntry) => textOf2(ntry.Sts?.Cd ?? ntry.Sts).trim().toUpperCase();
  function balances(stmt) {
    const out = {};
    for (const bal of arr3(stmt.Bal)) {
      const code = textOf2(bal?.Tp?.CdOrPrtry?.Cd).toUpperCase();
      const amount2 = signedAmount(bal);
      if (!amount2) continue;
      if ((code === "OPBD" || code === "PRCD") && out.opening === void 0) out.opening = amount2;
      if (code === "CLBD") out.closing = amount2;
    }
    return out;
  }
  function readCamt(xml2) {
    let doc;
    try {
      doc = parser3.parse(xml2);
    } catch {
      throw new BankFileError("camt", "This XML file could not be read.");
    }
    const root = doc.Document;
    const container = root?.BkToCstmrStmt ?? root?.BkToCstmrAcctRpt ?? root?.BkToCstmrDbtCdtNtfctn;
    if (!container) throw new BankFileError("camt", "This XML file is not a CAMT bank statement (camt.052, .053 or .054).");
    const statements = arr3(container.Stmt ?? container.Rpt ?? container.Ntfctn);
    const transactions = [];
    const candidates = [];
    let iban = "", bic = "", bankName2 = "", currency = "EUR", skipped = 0;
    for (const stmt of statements) {
      iban || (iban = ibanOf(stmt.Acct));
      bic || (bic = textOf2(stmt.Acct?.Svcr?.FinInstnId?.BIC ?? stmt.Acct?.Svcr?.FinInstnId?.BICFI));
      bankName2 || (bankName2 = cleanText(textOf2(stmt.Acct?.Svcr?.FinInstnId?.Nm)));
      currency = textOf2(stmt.Acct?.Ccy) || currency;
    }
    const vr = isVrBank(iban, bic);
    for (const stmt of statements) {
      const { opening, closing: closing2 } = balances(stmt);
      const start = transactions.length;
      for (const ntry of arr3(stmt.Ntry)) {
        const amount2 = signedAmount(ntry);
        const bookingDate2 = dateOnly(ntry.BookgDt?.Dt ?? ntry.BookgDt?.DtTm) ?? dateOnly(ntry.ValDt?.Dt ?? ntry.ValDt?.DtTm);
        if (PENDING.has(statusOf(ntry)) || !amount2 || !bookingDate2) {
          skipped++;
          continue;
        }
        const out = amount2.startsWith("-");
        const details = arr3(ntry.NtryDtls).flatMap((d) => arr3(d?.TxDtls));
        const tx = details[0];
        const parties = tx?.RltdPties ?? {};
        const creditor = nameOf(parties.Cdtr) || nameOf(parties.UltmtCdtr);
        const debtor = nameOf(parties.Dbtr) || nameOf(parties.UltmtDbtr);
        const counterparty = (out ? creditor || debtor : debtor || creditor) || null;
        const counterpartyIban = ibanOf(out ? parties.CdtrAcct : parties.DbtrAcct);
        const checkedIban = entryCounterpartyIban(ntry);
        const description = batchText(details.map(remittance)) || cleanText(textOf2(ntry.AddtlNtryInf)) || "(no description)";
        const ccy = (ntry.Amt && typeof ntry.Amt === "object" ? ntry.Amt["@_Ccy"] : void 0) || currency;
        transactions.push({
          bookingDate: bookingDate2,
          valueDate: dateOnly(ntry.ValDt?.Dt ?? ntry.ValDt?.DtTm),
          amount: amount2,
          currency: ccy,
          description,
          counterparty,
          ...checkedIban ? { counterpartyIban: checkedIban } : {},
          raw: ntry
        });
        if (vr) candidates.push(vrCamtId(ntry));
        else {
          const ref = textOf2(ntry.AcctSvcrRef) || textOf2(tx?.Refs?.AcctSvcrRef);
          const fields2 = [
            bookingDate2.slice(0, 10),
            amount2,
            description,
            counterparty ?? "",
            counterpartyIban,
            textOf2(tx?.Refs?.EndToEndId)
          ].join("|");
          candidates.push({ id: ref && ref !== "NOTPROVIDED" ? ref : hashId(fields2), fields: fields2 });
        }
      }
      const own = transactions.slice(start);
      if (opening !== void 0 && own.length > 0 && own.every((t, i2) => i2 === 0 || own[i2 - 1].bookingDate <= t.bookingDate)) {
        let running = opening;
        const after = own.map((t) => running = addAmounts(running, t.amount));
        if (closing2 === void 0 || sameAmount(running, closing2)) own.forEach((t, i2) => {
          t.balance = after[i2];
        });
      }
    }
    const ids = withOccurrences(candidates);
    const account = { name: accountName(bankName2 || "Bank", iban || void 0), currency };
    if (iban) account.iban = iban;
    return {
      format: "camt",
      account,
      transactions: transactions.map((t, i2) => ({ externalId: ids[i2], ...t })),
      skipped
    };
  }

  // src/engine/readers/guess.ts
  var WORDS = {
    date: [
      "buchungstag",
      "buchungsdatum",
      "buchung",
      "datum",
      "date",
      "bookingdate",
      "completeddate",
      "transactiondate",
      "umsatztag",
      "belegdatum",
      "booked",
      "tag"
    ],
    valueDate: ["valuta", "valutadatum", "wertstellung", "wert", "valuedate"],
    amount: ["betrag", "umsatz", "amount", "summe", "value", "total", "betrageur", "amounteur"],
    debit: ["soll", "belastung", "debit", "ausgang", "ausgabe", "moneyout", "paidout", "withdrawal", "lastschrift"],
    credit: ["haben", "gutschrift", "credit", "eingang", "einnahme", "moneyin", "paidin", "deposit"],
    balance: ["saldo", "kontostand", "balance", "guthaben", "saldonachbuchung", "runningbalance"],
    counterparty: [
      "zahlungsbeteiligter",
      "namezahlungsbeteiligter",
      "beguenstigter",
      "zahlungspflichtiger",
      "empfaenger",
      "auftraggeber",
      "name",
      "payee",
      "payer",
      "partner",
      "partnername",
      "merchant",
      "counterparty",
      "haendler",
      "gegenpartei",
      "gegenseite",
      "beguenstigterzahlungspflichtiger",
      "auftraggeberempfaenger",
      "recipient",
      "sender"
    ],
    text: [
      "verwendungszweck",
      "zweck",
      "purpose",
      "reference",
      "paymentreference",
      "referenz",
      "memo",
      "description",
      "beschreibung",
      "details",
      "buchungsdetails",
      "text",
      "notes",
      "notiz",
      "betreff",
      "vorgangverwendungszweck",
      "information",
      "buchungsinformation"
    ],
    kind: ["buchungstext", "umsatzart", "vorgang", "type", "transactiontype", "art", "buchungsart", "umsatztyp", "typ"],
    iban: ["iban", "kontonummer", "accountnumber", "konto", "partneriban", "ibanzahlungsbeteiligter", "kontonummeriban"],
    accountIban: ["auftragskonto", "ibanauftragskonto", "eigeneiban", "ownaccount"],
    currency: ["waehrung", "currency", "ccy"],
    reference: ["transactionid", "transaktionsid", "transaktionscode", "referenznummer", "buchungsreferenz", "id"],
    status: ["status", "state", "zustand", "info"]
  };
  function wordScore(header, role) {
    const key = headerKey(header);
    let best = 0;
    for (const word of WORDS[role]) {
      const fits = word.length <= 4 ? key === word || key === `${word}eur` : key.includes(word);
      if (fits && word.length > best) best = word.length;
    }
    return best;
  }
  var hasLetter = (v) => /\p{L}/u.test(v);
  var DE_DECIMAL = /\d,\d{1,2}(?!\d)/;
  var EN_DECIMAL = /\d\.\d{1,2}(?!\d)/;
  var isDateLike = (v) => DATE_FORMATS.some((f) => parseDate(v, f) !== null);
  var SIGN_VALUE = /^(s|h|soll|haben|d|c|db|cr|dbit|crdt|debit|credit|\+|-)$/i;
  function findHeader(rows) {
    for (let i2 = 0; i2 < Math.min(rows.length, 60); i2++) {
      const cells = trimRow(rows[i2]);
      if (cells.some((v) => /^(plannedamount|forecastamount|budgetamount)/.test(headerKey(v)))) continue;
      const filled = cells.filter(Boolean);
      if (filled.length < 3 || filled.length < cells.length * 0.6) continue;
      if (!filled.every((v) => hasLetter(v) && !isDateLike(v) && !DE_DECIMAL.test(v) && !EN_DECIMAL.test(v))) continue;
      const next = rows.slice(i2 + 1, i2 + 6).map(trimRow).filter((r) => r.length > 0);
      if (next.some((r) => r.length >= cells.length - 2 && r.some(isDateLike))) return i2;
    }
    return -1;
  }
  function bestDateFormat(values) {
    let best = "DD.MM.YYYY", share = 0;
    const full = [];
    for (const format of DATE_FORMATS) {
      const ok = values.filter((v) => parseDate(v, format) !== null).length / Math.max(values.length, 1);
      if (ok > share) {
        best = format;
        share = ok;
      }
      if (ok === 1) full.push(format);
    }
    let ambiguous = false;
    if (full.includes("DD/MM/YYYY") && full.includes("MM/DD/YYYY")) {
      const sorted = (format) => {
        const dates = values.map((v) => parseDate(v, format));
        const up = dates.every((d, i2) => i2 === 0 || dates[i2 - 1] <= d), down = dates.every((d, i2) => i2 === 0 || dates[i2 - 1] >= d);
        return up || down;
      };
      const dm = sorted("DD/MM/YYYY"), md = sorted("MM/DD/YYYY");
      best = md && !dm ? "MM/DD/YYYY" : "DD/MM/YYYY";
      ambiguous = true;
    }
    return { format: best, share, ambiguous };
  }
  function balanceFits(amounts, balances2) {
    let fits = 0, pairs = 0;
    for (let i2 = 1; i2 < amounts.length; i2++) {
      const a0 = amounts[i2 - 1], a1 = amounts[i2], b0 = balances2[i2 - 1], b1 = balances2[i2];
      if (!a0 || !a1 || !b0 || !b1) continue;
      pairs++;
      if (sameAmount(addAmounts(b0, a1), b1) || sameAmount(addAmounts(b1, a0), b0)) fits++;
    }
    return pairs === 0 ? 0 : fits / pairs;
  }
  var filledAmount = (v) => v !== null && !/^-?0\.0+$/.test(v);
  function complementary(a, b) {
    return !a.some((v, i2) => filledAmount(v) && filledAmount(b[i2])) && a.some(filledAmount) && b.some(filledAmount);
  }
  function outAndIn(out, inn) {
    return out.map((v, i2) => filledAmount(v) ? `-${v.replace(/^-/, "")}` : filledAmount(inn[i2]) ? inn[i2].replace(/^-/, "") : null);
  }
  function findTableStart(rows) {
    const headerRow = findHeader(rows);
    if (headerRow >= 0) return { headerRow, width: trimRow(rows[headerRow]).length };
    const filled = rows.filter((r) => r.some((v) => v.trim() !== ""));
    const sample = filled.slice(0, 5);
    const width = sample[0]?.length ?? 0;
    const isData = (r) => r.length === width && trimRow(r).length >= 3 && r.some(isDateLike) && r.some((v) => !isDateLike(v) && (DE_DECIMAL.test(v) || EN_DECIMAL.test(v)));
    return sample.length > 0 && sample.every(isData) ? { headerRow: -1, width } : null;
  }
  function guessCsvLayout(text3) {
    return analyseCsv(text3).guess;
  }
  function analyseCsv(text3) {
    const separator = detectSeparator(text3);
    const rows = checkedCsvRows(text3, separator);
    const table = findTableStart(rows);
    if (!table) throw new BankFileError("noTable", "No table with a header row and dates was found in this file.");
    const { headerRow, width } = table;
    const header = headerRow >= 0 ? trimRow(rows[headerRow]) : [];
    const names2 = headerRow >= 0 ? header : Array.from({ length: width }, (_, i2) => `Column ${i2 + 1}`);
    const data = rows.slice(headerRow + 1).map(trimRow).filter((r) => r.length >= Math.ceil(width / 2) && r.some(isDateLike));
    const column = (j) => data.map((r) => r[j] ?? "");
    let de = 0, en = 0;
    for (const r of data) for (const v of r) {
      if (isDateLike(v)) continue;
      if (DE_DECIMAL.test(v)) de++;
      if (EN_DECIMAL.test(v)) en++;
    }
    const numberFormat = en > de ? "en" : "de";
    const decimalMark = numberFormat === "de" ? DE_DECIMAL : EN_DECIMAL;
    const columns = [];
    for (let j = 0; j < width; j++) {
      const all = column(j), values = all.filter(Boolean);
      let kind = "text";
      let dateFormat3, ambiguous = false;
      if (values.length === 0) kind = "empty";
      else {
        const date2 = bestDateFormat(values);
        const amounts = values.filter((v) => parseAmountStrict(v, numberFormat) !== null).length / values.length;
        const decimals = values.filter((v) => decimalMark.test(v)).length / values.length;
        if (date2.share >= 0.9) {
          kind = "date";
          dateFormat3 = date2.format;
          ambiguous = date2.ambiguous;
        } else if (values.filter((v) => normalizeIban(v)).length / values.length >= 0.8) kind = "iban";
        else if (amounts >= 0.9 && decimals >= 0.5) kind = "amount";
        else if (values.every((v) => SIGN_VALUE.test(v)) && new Set(values.map((v) => v.toLowerCase())).size <= 4) kind = "sign";
        else if (values.every((v) => /^[A-Z]{3}$/.test(v)) && new Set(values).size <= 3) kind = "currency";
        else if (values.every((v) => /^[\d\s/-]+$/.test(v))) kind = "number";
      }
      columns.push({ index: j, header: names2[j], kind, samples: values.slice(0, 3), values: all, dateFormat: dateFormat3, ambiguous });
    }
    const roles = {};
    const unsure = /* @__PURE__ */ new Set();
    const taken = /* @__PURE__ */ new Set();
    const take = (role, j) => {
      roles[role] = j;
      taken.add(j);
    };
    const byWord = (role, kinds) => columns.filter((col) => !taken.has(col.index) && kinds.includes(col.kind) && wordScore(col.header, role) > 0).sort((a, b) => wordScore(b.header, role) - wordScore(a.header, role))[0];
    const dates = columns.filter((col) => col.kind === "date");
    const booking = [...dates].sort((a, b) => wordScore(b.header, "date") - wordScore(b.header, "valueDate") - (wordScore(a.header, "date") - wordScore(a.header, "valueDate")) || a.index - b.index)[0];
    if (booking) {
      take("date", booking.index);
      if (wordScore(booking.header, "date") === 0) unsure.add("date");
      const value = dates.find((col) => col !== booking && wordScore(col.header, "valueDate") > 0) ?? dates.find((col) => col !== booking);
      if (value) take("valueDate", value.index);
    }
    const amountCols = columns.filter((col) => col.kind === "amount");
    const parsed = (j) => columns[j].values.map((v) => parseAmountStrict(v, numberFormat));
    const balanceWord = byWord("balance", ["amount"]);
    if (balanceWord) take("balance", balanceWord.index);
    const debitWord = byWord("debit", ["amount"]), creditWord = byWord("credit", ["amount"]);
    const amountWord = byWord("amount", ["amount"]);
    if (amountWord) take("amount", amountWord.index);
    else if (debitWord && creditWord) {
      take("debit", debitWord.index);
      take("credit", creditWord.index);
    } else {
      let rest = amountCols.filter((col) => !taken.has(col.index));
      if (roles.balance === void 0) {
        const movesBy = (b) => rest.some((a) => a.index !== b && balanceFits(parsed(a.index), parsed(b)) >= 0.8) || rest.some((x2) => rest.some((y) => x2 !== y && x2.index !== b && y.index !== b && complementary(parsed(x2.index), parsed(y.index)) && balanceFits(outAndIn(parsed(x2.index), parsed(y.index)), parsed(b)) >= 0.8));
        const moving = rest.find((col) => movesBy(col.index));
        if (moving) {
          take("balance", moving.index);
          rest = rest.filter((col) => col !== moving);
        }
      }
      const pair = rest.length === 2 ? debitCredit(rest[0].index, rest[1].index) : null;
      if (pair) {
        take("debit", pair.debit);
        take("credit", pair.credit);
        if (!pair.sure) unsure.add("amount");
      } else {
        const balanceCol = roles.balance;
        const fitting = balanceCol !== void 0 ? rest.find((col) => balanceFits(parsed(col.index), parsed(balanceCol)) >= 0.8) : void 0;
        if (fitting) take("amount", fitting.index);
        else if (rest[0]) {
          take("amount", rest[0].index);
          unsure.add("amount");
        }
      }
    }
    if (roles.balance === void 0 && roles.amount !== void 0) {
      const fitting = amountCols.find((col) => !taken.has(col.index) && balanceFits(parsed(roles.amount), parsed(col.index)) >= 0.8);
      if (fitting) take("balance", fitting.index);
    }
    function debitCredit(a, b) {
      const pa = parsed(a), pb = parsed(b);
      if (!complementary(pa, pb)) return null;
      if (debitWord?.index === a || creditWord?.index === b) return { debit: a, credit: b, sure: true };
      if (debitWord?.index === b || creditWord?.index === a) return { debit: b, credit: a, sure: true };
      if (roles.balance !== void 0) {
        const balance = parsed(roles.balance);
        if (balanceFits(outAndIn(pa, pb), balance) >= 0.8) return { debit: a, credit: b, sure: true };
        if (balanceFits(outAndIn(pb, pa), balance) >= 0.8) return { debit: b, credit: a, sure: true };
      }
      if (pa.filter(filledAmount).every((v) => v.startsWith("-"))) return { debit: a, credit: b, sure: true };
      if (pb.filter(filledAmount).every((v) => v.startsWith("-"))) return { debit: b, credit: a, sure: true };
      return { debit: a, credit: b, sure: false };
    }
    const sign = columns.find((col) => col.kind === "sign");
    const anyNegative = roles.amount !== void 0 && parsed(roles.amount).some((a) => a?.startsWith("-"));
    if (sign && roles.amount !== void 0 && !anyNegative) taken.add(sign.index);
    else if (roles.amount !== void 0 && !anyNegative) unsure.add("sign");
    for (const col of columns.filter((c) => c.kind === "iban" && !taken.has(c.index))) {
      const distinct = new Set(col.values.filter(Boolean).map((v) => v.replace(/\s/g, "")));
      if (distinct.size === 1 && data.length > 1 || wordScore(col.header, "accountIban") > 0) {
        if (roles.accountIban === void 0) take("accountIban", col.index);
      } else if (roles.iban === void 0) take("iban", col.index);
    }
    const currency = byWord("currency", ["currency", "text"]) ?? columns.find((col) => col.kind === "currency" && !taken.has(col.index));
    if (currency) take("currency", currency.index);
    const status = byWord("status", ["text"]);
    if (status && new Set(status.values).size <= 6) take("status", status.index);
    const reference = byWord("reference", ["text", "number"]);
    if (reference && new Set(reference.values.filter(Boolean)).size === reference.values.filter(Boolean).length) take("reference", reference.index);
    const bookingType = (col) => col.values.filter(Boolean).every((v) => /^(lastschrift|sepa.lastschrift|überweisung|sepa.überweisung|gutschrift|kartenzahlung|kartenverfügung|dauerauftrag|card payment|transfer)$/i.test(v.trim()));
    const purpose = columns.filter((col) => col.kind === "text" && !taken.has(col.index) && wordScore(col.header, "text") > wordScore(col.header, "kind") && wordScore(col.header, "text") > 0).sort((a, b) => wordScore(b.header, "text") - wordScore(a.header, "text"))[0];
    if (purpose) take("text", purpose.index);
    const type = columns.filter((col) => col.kind === "text" && !taken.has(col.index) && wordScore(col.header, "kind") > 0 && bookingType(col)).sort((a, b) => wordScore(b.header, "kind") - wordScore(a.header, "kind"))[0];
    if (type) take("kind", type.index);
    for (const role of ["kind", "counterparty", "text"]) {
      if (roles[role] !== void 0) continue;
      const col = byWord(role, ["text"]);
      if (col) take(role, col.index);
    }
    const freeText = columns.filter((col) => col.kind === "text" && !taken.has(col.index));
    const avg = (col) => col.values.reduce((n, v) => n + v.length, 0) / Math.max(col.values.length, 1);
    if (roles.text === void 0) {
      const longest = [...freeText].sort((a, b) => avg(b) - avg(a))[0];
      if (longest) {
        take("text", longest.index);
        unsure.add("text");
      }
    }
    if (roles.counterparty === void 0) unsure.add("counterparty");
    const missing = [];
    if (roles.date === void 0) missing.push("date");
    if (roles.amount === void 0 && (roles.debit === void 0 || roles.credit === void 0)) missing.push("amount");
    const info = columns.map(({ index, header: h, kind, samples, dateFormat: f }) => ({ index, header: h, kind, samples, ...f ? { dateFormat: f } : {} }));
    const dateCol = roles.date !== void 0 ? columns[roles.date] : void 0;
    const dateFormat2 = dateCol?.dateFormat ?? "DD.MM.YYYY";
    if (dateCol?.ambiguous) unsure.add("dateFormat");
    if (missing.length > 0) {
      return {
        guess: { layout: null, confidence: 0, unsure: [...unsure], missing, separator, header, headerRow, columns: info, preview: [] },
        columns,
        rows,
        payments: []
      };
    }
    const layout2 = {
      version: 1,
      separator,
      header,
      ...headerRow < 0 ? { columnCount: width } : {},
      dateFormat: dateFormat2,
      numberFormat,
      columns: {
        date: roles.date,
        ...roles.valueDate !== void 0 ? { valueDate: roles.valueDate } : {},
        ...roles.amount !== void 0 ? { amount: roles.amount } : { debit: roles.debit, credit: roles.credit },
        ...sign && roles.amount !== void 0 && !anyNegative ? { sign: sign.index } : {},
        ...roles.counterparty !== void 0 ? { counterparty: [roles.counterparty] } : {},
        ...roles.text !== void 0 ? { text: [roles.text] } : {},
        ...roles.kind !== void 0 ? { kind: roles.kind } : {},
        ...roles.iban !== void 0 ? { iban: roles.iban } : {},
        ...roles.accountIban !== void 0 ? { accountIban: roles.accountIban } : {},
        ...roles.balance !== void 0 ? { balance: roles.balance } : {},
        ...roles.currency !== void 0 ? { currency: roles.currency } : {},
        ...roles.reference !== void 0 ? { reference: roles.reference } : {},
        ...roles.status !== void 0 ? { status: roles.status } : {}
      },
      ...roles.status !== void 0 ? { skipStatus: ["vorgemerkt", "pending", "offen", "reverted", "declined", "failed", "storniert"] } : {}
    };
    const read2 = readTable(rows, headerRow, layout2);
    const rowsRead = read2.transactions.length / Math.max(data.length, 1);
    let confidence = Math.min(1, rowsRead);
    if (unsure.has("date")) confidence *= 0.85;
    if (unsure.has("dateFormat")) confidence *= 0.7;
    if (unsure.has("amount")) confidence *= 0.75;
    if (unsure.has("sign")) confidence *= 0.7;
    if (unsure.has("text")) confidence *= 0.9;
    if (unsure.has("counterparty")) confidence *= 0.9;
    return {
      guess: {
        layout: layout2,
        confidence: Math.round(confidence * 100) / 100,
        unsure: [...unsure],
        missing,
        separator,
        header,
        headerRow,
        columns: info,
        preview: read2.transactions.slice(0, 5)
      },
      columns,
      rows,
      payments: read2.transactions
    };
  }

  // src/engine/readers/mt940.ts
  function fields(text3) {
    const out = [];
    for (const line of text3.replace(/\r\n?/g, "\n").split("\n")) {
      const m = /^:(\d{2}[A-Z]?):(.*)$/.exec(line);
      if (m) out.push({ tag: m[1], value: m[2] });
      else if (/^-}?\s*$/.test(line) || line.startsWith("{")) out.push({ tag: "end", value: "" });
      else if (out.length > 0 && out[out.length - 1].tag !== "end") out[out.length - 1].value += `
${line}`;
    }
    return out;
  }
  function date6(value) {
    const m = /^(\d{2})(\d{2})(\d{2})$/.exec(value);
    if (!m || +m[2] < 1 || +m[2] > 12 || +m[3] < 1 || +m[3] > 31) return null;
    return `20${m[1]}-${m[2]}-${m[3]}`;
  }
  var amountOf = (value) => parseAmountStrict(value.endsWith(",") ? `${value}00` : value, "de");
  function balanceOf(value) {
    const m = /^([CD])(\d{6})([A-Z]{3})([\d,]+)/.exec(value.trim());
    const amount2 = m ? amountOf(m[4]) : null;
    if (!m || !amount2) return null;
    return { amount: m[1] === "D" ? negate(amount2) : amount2, currency: m[3] };
  }
  var LINE_61 = /^(\d{6})(\d{4})?(RC|RD|C|D)([A-Z])?(\d+,\d*)([NFS][A-Z0-9]{3})(.*)$/;
  function bookingDate(valueDate, entry) {
    if (!entry) return valueDate;
    let year = +valueDate.slice(0, 4);
    const valueMonth = +valueDate.slice(5, 7), month = +entry.slice(0, 2);
    if (month - valueMonth > 6) year--;
    if (valueMonth - month > 6) year++;
    return `${year}-${entry.slice(0, 2)}-${entry.slice(2, 4)}`;
  }
  function joinSubfields(parts) {
    let text3 = "";
    parts.forEach((part, i2) => {
      text3 += (i2 > 0 && parts[i2 - 1].length < 27 ? " " : "") + part;
    });
    return text3.replace(/\s+/g, " ").trim();
  }
  function details86(value) {
    const joined = value.replace(/\n/g, "");
    const m = /^(\d{3})(\D)/.exec(joined);
    if (!m) return { kind: "", text: cleanText(joined), name: "", iban: null };
    const separator = m[2];
    const sub = /* @__PURE__ */ new Map();
    const parts = joined.slice(4).split(new RegExp(`\\${separator}(\\d{2})`));
    for (let i2 = 1; i2 < parts.length; i2 += 2) sub.set(parts[i2], (sub.get(parts[i2]) ?? "") + parts[i2 + 1]);
    const codes = (from2, to) => {
      const out = [];
      for (let n = from2; n <= to; n++) if (sub.has(String(n))) out.push(sub.get(String(n)));
      return out;
    };
    const purpose = joinSubfields([...codes(20, 29), ...codes(60, 63)]);
    return {
      kind: cleanText(sub.get("00")),
      text: sepaPaymentText(purpose),
      name: joinSubfields(codes(32, 33)),
      iban: normalizeIban(sub.get("31") ?? "")
      // ?31 holds an IBAN or an old account number; only an IBAN counts
    };
  }
  function readMt940(text3) {
    const list2 = fields(text3);
    if (!list2.some((f) => f.tag === "61") && !list2.some((f) => f.tag === "20")) {
      throw new BankFileError("mt940", "This file is not an MT940 statement.");
    }
    const transactions = [];
    let iban, accountNumber = "", currency = "EUR", skipped = 0;
    let statement = -1, intraday = false;
    const openings = /* @__PURE__ */ new Map(), closings = /* @__PURE__ */ new Map();
    const intradayStatements = /* @__PURE__ */ new Set();
    let last2 = null;
    for (const field2 of list2) {
      if (field2.tag === "20") {
        statement++;
        intraday = false;
        last2 = null;
        continue;
      }
      if (field2.tag === "end") {
        last2 = null;
        continue;
      }
      if (field2.tag === "25") {
        const value = field2.value.trim();
        iban ?? (iban = findIban(value));
        accountNumber || (accountNumber = value.split("/").pop().replace(/[^0-9]/g, ""));
      } else if (field2.tag === "34F" || field2.tag === "13D" || field2.tag === "13") {
        intraday = true;
        intradayStatements.add(statement);
      } else if (field2.tag === "60F" || field2.tag === "60M") {
        const bal = balanceOf(field2.value);
        if (bal) {
          openings.set(statement, bal.amount);
          currency = bal.currency;
        }
      } else if (field2.tag === "62F" || field2.tag === "62M") {
        const bal = balanceOf(field2.value);
        if (bal) closings.set(statement, bal.amount);
        last2 = null;
      } else if (field2.tag === "61") {
        last2 = null;
        const [first] = field2.value.split("\n");
        const m = LINE_61.exec(first.trim());
        const valueDate = m ? date6(m[1]) : null;
        const amount2 = m ? amountOf(m[5]) : null;
        if (!m || !valueDate || !amount2 || intraday) {
          skipped++;
          continue;
        }
        const debit = m[3] === "D" || m[3] === "RC";
        last2 = {
          bookingDate: `${bookingDate(valueDate, m[2])}T00:00:00.000Z`,
          valueDate: `${valueDate}T00:00:00.000Z`,
          amount: debit ? negate(amount2) : amount2,
          currency,
          description: "(no description)",
          counterparty: null,
          raw: { ":61:": field2.value, ":86:": "" },
          idFields: field2.value.trim(),
          statement
        };
        transactions.push(last2);
      } else if (field2.tag === "86" && last2) {
        const d = details86(field2.value);
        last2.description = d.text || d.kind || d.name || "(no description)";
        last2.counterparty = d.name || null;
        if (d.iban) last2.counterpartyIban = d.iban;
        last2.raw[":86:"] = field2.value;
        last2.idFields += `${field2.value.replace(/\s+/g, " ").trim()}`;
        last2 = null;
      }
    }
    for (const [index, opening] of openings) {
      if (intradayStatements.has(index)) continue;
      const own = transactions.filter((t) => t.statement === index);
      if (!own.every((t, i2) => i2 === 0 || own[i2 - 1].bookingDate <= t.bookingDate)) continue;
      let running = opening;
      const after = own.map((t) => running = addAmounts(running, t.amount));
      const closing2 = closings.get(index);
      if (own.length > 0 && (closing2 === void 0 || sameAmount(running, closing2))) own.forEach((t, i2) => {
        t.balance = after[i2];
      });
    }
    const ids = bookingIds(transactions.map((t) => t.idFields));
    const account = { name: iban ? accountName("Bank", iban) : accountNumber ? `Bank \u2022\u2022${accountNumber.slice(-4)}` : "Bank", currency };
    if (iban) account.iban = iban;
    return {
      format: "mt940",
      account,
      transactions: transactions.map(({ idFields: _, statement: __, ...t }, i2) => ({ externalId: ids[i2], ...t })),
      skipped
    };
  }

  // src/engine/readers/read.ts
  var isPaypalHeader = (row) => {
    const keys = new Set(row.map(headerKey));
    return (keys.has("transaktionscode") || keys.has("transactionid")) && ["netto", "net", "brutto", "gross"].some((k) => keys.has(k));
  };
  function savedLayoutFor(text3, saved) {
    const bySeparator = /* @__PURE__ */ new Map();
    const ordered = [...saved].sort((a, b) => Number(a.header.length === 0) - Number(b.header.length === 0));
    for (const layout2 of ordered) {
      if (!bySeparator.has(layout2.separator)) bySeparator.set(layout2.separator, splitCsv(text3.slice(0, 2e5), layout2.separator));
      const headerRow = findTable(bySeparator.get(layout2.separator), layout2);
      if (headerRow !== null) return { layout: layout2, headerRow };
    }
    return null;
  }
  function detectBankFile(text3, savedLayouts = []) {
    const head = text3.replace(/^\uFEFF/, "").trimStart();
    if (head === "") return { format: "unknown", reason: "empty" };
    if (head.startsWith("PK")) return { format: "unknown", reason: "zip" };
    if (head.startsWith("<")) {
      if (!/<(\w+:)?Document[\s>]/.test(head) || !/BkToCstmr/.test(head)) return { format: "unknown", reason: "xml" };
      const message = /camt\.05[234]\.\d{3}\.\d{2}/.exec(head)?.[0];
      return message ? { format: "camt", message } : { format: "camt" };
    }
    if (/^:20:/m.test(head) && /^:(61|60F|60M):/m.test(head)) return { format: "mt940" };
    const separator = detectSeparator(head);
    const rows = splitCsv(head, separator);
    const paypalRow = rows.slice(0, 5).findIndex(isPaypalHeader);
    if (paypalRow >= 0) return { format: "paypal", separator, headerRow: paypalRow };
    const saved = savedLayoutFor(head, savedLayouts);
    if (saved) return { format: "csv", separator: saved.layout.separator, headerRow: saved.headerRow, layout: saved.layout };
    const known = findProfile(rows);
    const layout2 = known ? profileLayout(known.profile, rows, known.headerRow, separator) : null;
    if (known && layout2) {
      return {
        format: "csv",
        separator,
        headerRow: known.headerRow,
        layout: layout2,
        profile: { id: known.profile.id, bank: known.profile.bank },
        ...profileDateAmbiguous(known.profile, rows, known.headerRow, layout2) ? { dateAmbiguous: true } : {}
      };
    }
    const table = findTableStart(rows);
    return table ? { format: "csv", separator, headerRow: table.headerRow } : { format: "unknown", reason: "noTable" };
  }
  function isoTransactions(file) {
    return file.transactions.map(({ bookingDate: bookingDate2, valueDate, ...txn }) => ({
      ...txn,
      bookingDate: bookingDate2.toISOString(),
      ...valueDate === void 0 ? {} : { valueDate: valueDate?.toISOString() ?? null }
    }));
  }
  var findKnown = (id) => BANK_PROFILES.find((p) => p.id === id);
  var bankName = (profile) => profile.variant ? `${profile.bank} (${profile.variant})` : profile.bank;
  function dateConfirmation(rows, headerRow, layout2) {
    if (layout2.profile === "volksbank" && headerRow === 0) layout2 = { ...layout2, idStyle: "vrbank" };
    const data = rows.slice(headerRow + 1);
    const c = layout2.columns;
    const names2 = layout2.header.length ? layout2.header : Array.from({ length: layout2.columnCount ?? 0 }, (_, i2) => `Column ${i2 + 1}`);
    const columns = names2.map((header, index) => ({
      index,
      header,
      kind: index === c.date || index === c.valueDate ? "date" : [c.amount, c.debit, c.credit, c.balance, ...c.fees ?? [], ...c.addAmounts ?? []].includes(index) ? "amount" : [c.iban, c.accountIban].includes(index) ? "iban" : index === c.currency ? "currency" : index === c.sign ? "sign" : "text",
      samples: data.map((r) => r[index] ?? "").filter(Boolean).slice(0, 3),
      ...index === layout2.columns.date ? { dateFormat: layout2.dateFormat } : {}
    }));
    return {
      layout: layout2,
      confidence: 0.7,
      unsure: ["dateFormat"],
      missing: [],
      separator: layout2.separator,
      header: layout2.header,
      headerRow,
      columns,
      preview: readTable(rows, headerRow, layout2).transactions.slice(0, 5)
    };
  }
  function recordCounterpartyIban(record, profile) {
    if (!record || typeof record !== "object" || profile.columns.iban === void 0) return void 0;
    const names2 = [profile.columns.iban].flat().filter((name) => typeof name === "string");
    for (const name of names2) {
      const value = record[name];
      const iban = typeof value === "string" ? normalizeIban(value) : null;
      if (iban) return iban;
    }
    return void 0;
  }
  function readVrBank(text3, profile, bank = profile.bank) {
    const parsed = parseVrBankCsv(text3);
    const dateColumns = ["Buchungstag", "Buchung", "Buchungsdatum"];
    const kept = parsed.transactions.filter((t) => {
      const raw = t.raw;
      const value = dateColumns.map((c) => raw[c]).find((v) => v !== void 0 && v.trim() !== "") ?? "";
      return DATE_FORMATS.some((f) => parseDate(value, f) !== null);
    });
    const ids = withOccurrences(kept.map((t) => ({
      id: t.externalId,
      fields: `${t.bookingDate.toISOString()}|${t.amount}|${t.description}|${t.counterparty ?? ""}`
    })));
    const canonical = (v) => parseAmountStrict(v, "en") ?? v;
    const transactions = isoTransactions({ ...parsed, transactions: kept }).map((t, i2) => {
      const counterpartyIban = recordCounterpartyIban(t.raw, profile);
      return {
        ...t,
        externalId: ids[i2],
        amount: canonical(t.amount),
        ...t.balance ? { balance: canonical(t.balance) } : {},
        ...counterpartyIban ? { counterpartyIban } : {}
      };
    });
    const name = bank === profile.bank ? parsed.account.name : accountName(bank, parsed.account.iban);
    const account = { name, currency: parsed.account.currency, ...parsed.account.iban ? { iban: parsed.account.iban } : {} };
    return {
      format: "csv",
      bank: { id: profile.id, name: bankName(profile) },
      account,
      transactions,
      skipped: parsed.transactions.length - kept.length
    };
  }
  function readBankFile(bytes, savedLayouts = []) {
    if (bytes[0] === 208 && bytes[1] === 207 && bytes[2] === 17 && bytes[3] === 224) {
      throw new BankFileError("xls", "Old Excel (.xls) files cannot be read. Export as CSV or save as .xlsx.");
    }
    if (isZip(bytes)) {
      const files = unzipBankFile(bytes);
      if (isXlsx(files)) return readBankText(xlsxText(files, savedLayouts), savedLayouts);
      return readArchive(archiveBankTexts(files, isBankText), (text4) => readBankText(text4, savedLayouts));
    }
    const { text: text3, encoding } = decodeBankFileWithEncoding(bytes);
    return { ...readBankText(text3, savedLayouts), encoding };
  }
  var isBankText = (text3) => detectBankFile(text3).format !== "unknown";
  var xlsxText = (files, saved) => xlsxTableText(files, (text3) => {
    const format = detectBankFile(text3, saved).format;
    return format === "csv" || format === "paypal";
  });
  function bankTableText(bytes, saved = []) {
    if (!isZip(bytes)) return decodeBankFileWithEncoding(bytes).text;
    const files = unzipBankFile(bytes);
    if (isXlsx(files)) return xlsxText(files, saved);
    const texts2 = archiveBankTexts(files, isBankText);
    if (texts2.length !== 1) throw new BankFileError("zipLayout", "A bank file inside this ZIP needs its columns confirmed. Import that file separately first.");
    return texts2[0];
  }
  function readBankText(text3, savedLayouts = []) {
    const detected = detectBankFile(text3, savedLayouts);
    switch (detected.format) {
      case "camt":
        return readCamt(text3);
      case "mt940":
        return readMt940(text3);
      case "paypal": {
        const rows = checkedCsvRows(text3, detected.separator).slice(detected.headerRow);
        const data = rows.slice(1).filter((r) => r.some((v) => v.trim() !== ""));
        if (data.length === 0) throw new BankFileError("noTable", "No readable booked payments were found in this file.");
        const width = Math.min(rows[0].length, data.reduce((n, row) => Math.max(n, row.length), 0));
        if (data.some((r) => r.length < width)) throw new BankFileError("unknown", "A payment row is cut off or has missing columns. Download the file again.");
        const table = rows.map((row) => row.map((v) => `"${v.replace(/"/g, '""')}"`).join(",")).join("\n");
        const parsed = parsePaypalCsv2(table);
        return {
          format: "paypal",
          bank: { id: "paypal", name: "PayPal" },
          account: { name: parsed.account.name, currency: parsed.account.currency },
          transactions: isoTransactions(parsed)
        };
      }
      case "csv": {
        const rows = checkedCsvRows(text3, detected.separator);
        const { layout: layout2, profile } = detected;
        const known = profile ? findKnown(profile.id) : void 0;
        if (layout2 && detected.dateAmbiguous) {
          return { format: "csv", transactions: [], needsLayout: dateConfirmation(rows, detected.headerRow, layout2) };
        }
        if (known?.reader === "vrbank" && detected.headerRow === 0 && layout2) {
          const checked4 = readTable(rows, detected.headerRow, layout2);
          const c = layout2.columns;
          const kept = rows.filter((r, i2) => i2 === 0 || parseDate(r[c.date] ?? "", layout2.dateFormat) !== null && parseAmountStrict(r[c.amount] ?? "", layout2.numberFormat) !== null);
          const changedDates = layout2.dateFormat === "DD/MM/YYYY";
          if (changedDates) for (let i2 = 1; i2 < kept.length; i2++) {
            kept[i2] = [...kept[i2]];
            for (const j of [c.date, c.valueDate]) if (j !== void 0) {
              kept[i2][j] = parseDate(kept[i2][j] ?? "", layout2.dateFormat) ?? "";
            }
          }
          const compatible = changedDates || kept.length !== rows.length || detected.separator === "	" || detected.separator === "|" ? kept.map((row) => row.map((v) => `"${v.replace(/"/g, '""')}"`).join(";")).join("\n") : text3;
          return { ...readVrBank(compatible, known, layout2.name), skipped: checked4.skipped };
        }
        if (layout2) {
          const file = readTable(rows, detected.headerRow, layout2);
          return known ? { ...file, bank: { id: known.id, name: bankName(known) } } : file;
        }
        return { format: "csv", transactions: [], needsLayout: guessCsvLayout(text3.replace(/^\uFEFF/, "")) };
      }
      case "unknown": {
        const messages = {
          empty: "The file is empty.",
          zip: "This is a ZIP archive; open it and import the files inside.",
          xml: "This XML file is not a CAMT bank statement (camt.052, .053 or .054).",
          noTable: "No table with a header row and dates was found in this file."
        };
        const code = detected.reason === "xml" ? "camt" : detected.reason;
        throw new BankFileError(code, messages[detected.reason]);
      }
    }
  }

  // src/engine/readers/readings.ts
  var MAX_READINGS = 4;
  var PREVIEW_PAYMENTS = 5;
  var ORDER = [
    "dateFormat",
    "debitCredit",
    "amount",
    "sign",
    "invertSign",
    "counterpartyText",
    "counterparty",
    "valueDate"
  ];
  var OTHER_DAY_ORDER = { "DD/MM/YYYY": "MM/DD/YYYY", "MM/DD/YYYY": "DD/MM/YYYY" };
  function usedColumns(layout2) {
    return new Set(Object.values(layout2.columns).flat().filter((i2) => typeof i2 === "number"));
  }
  function withColumns(layout2, change) {
    const columns = { ...layout2.columns, ...change };
    for (const key of Object.keys(columns)) if (columns[key] === void 0) delete columns[key];
    return { ...layout2, columns };
  }
  function alternatives(guess, columns, guessed) {
    const layout2 = guess.layout, c = layout2.columns;
    const unsure = new Set(guess.unsure);
    const used = usedColumns(layout2);
    const freeText = columns.filter((col) => col.kind === "text" && !used.has(col.index));
    const out = [];
    const offer = (reason, changed, doubted) => out.push({ layout: changed, reason, doubted });
    const otherOrder = OTHER_DAY_ORDER[layout2.dateFormat];
    if (otherOrder) offer("dateFormat", { ...layout2, dateFormat: otherOrder }, unsure.has("dateFormat"));
    if (c.debit !== void 0 && c.credit !== void 0 && unsure.has("amount")) {
      offer("debitCredit", withColumns(layout2, { debit: c.credit, credit: c.debit }), true);
    }
    if (c.amount !== void 0 && unsure.has("amount")) {
      for (const col of columns.filter((col2) => col2.kind === "amount" && !used.has(col2.index))) {
        offer("amount", withColumns(layout2, { amount: col.index }), true);
      }
    }
    if (c.amount !== void 0 && c.sign === void 0) {
      const amounts = (j) => columns[j].values.map((v) => parseAmountStrict(v, layout2.numberFormat));
      for (const col of columns.filter((col2) => col2.kind === "amount" && !used.has(col2.index))) {
        if (!complementary(amounts(c.amount), amounts(col.index))) continue;
        const [left, right] = [c.amount, col.index].sort((a, b) => a - b);
        const minus = (j) => amounts(j).filter((v) => v !== null && !/^-?0\.0+$/.test(v)).every((v) => v.startsWith("-"));
        const [debit, credit] = minus(right) && !minus(left) ? [right, left] : [left, right];
        const pair = { amount: void 0, debit, credit };
        offer("debitCredit", withColumns(layout2, pair), true);
        offer("debitCredit", withColumns(layout2, { ...pair, debit: credit, credit: debit }), true);
      }
    }
    if (c.amount !== void 0 && c.sign === void 0) {
      for (const col of columns.filter((col2) => col2.index !== c.date && col2.index !== c.amount)) {
        const marks = col.values.filter((v) => v.trim() !== "").map(signMark);
        if (marks.length > 0 && marks.every(Boolean) && marks.includes("debit") && marks.includes("credit")) {
          offer("sign", withColumns(layout2, { sign: col.index }), unsure.has("sign"));
        }
      }
      const proven2 = c.balance !== void 0 && balanceFits(guessed.map((t) => t.amount), guessed.map((t) => t.balance ?? null)) >= 0.8;
      if (!proven2) offer("invertSign", { ...layout2, invertSign: true }, unsure.has("sign"));
    }
    const party = c.counterparty, text3 = c.text;
    const unsureText = unsure.has("text") || unsure.has("counterparty");
    if (party?.length && text3?.length) offer("counterpartyText", withColumns(layout2, { counterparty: text3, text: party }), unsureText);
    else if (text3?.length) {
      const longest = [...freeText].sort((a, b) => average(b) - average(a))[0];
      offer("counterpartyText", withColumns(layout2, { counterparty: text3, text: longest ? [longest.index] : void 0 }), unsureText);
      if (longest) offer("counterparty", withColumns(layout2, { counterparty: [longest.index] }), unsureText);
    } else if (party?.length) offer("counterpartyText", withColumns(layout2, { counterparty: void 0, text: party }), unsureText);
    if (c.valueDate !== void 0) offer("valueDate", withColumns(layout2, { date: c.valueDate, valueDate: c.date }), unsure.has("date"));
    const rank = (x2) => (x2.doubted ? 0 : ORDER.length) + ORDER.indexOf(x2.reason);
    return out.map((x2, i2) => ({ x: x2, i: i2 })).sort((a, b) => rank(a.x) - rank(b.x) || a.i - b.i).map(({ x: x2 }) => x2);
  }
  var average = (col) => col.values.reduce((n, v) => n + v.length, 0) / Math.max(col.values.length, 1);
  var shown = (preview) => JSON.stringify(preview.map((t) => [t.bookingDate.slice(0, 10), t.counterparty ?? "", t.description, t.amount]));
  function readingsOfUnknownText(text3, savedLayouts = []) {
    const clean2 = text3.replace(/^\uFEFF/, "");
    const detected = detectBankFile(clean2, savedLayouts);
    if (detected.format !== "csv") return [];
    if (detected.layout) {
      if (!detected.dateAmbiguous) return [];
      const rows2 = checkedCsvRows(clean2, detected.separator);
      const first = dateConfirmation(rows2, detected.headerRow, detected.layout).layout;
      return [first, { ...first, dateFormat: OTHER_DAY_ORDER[first.dateFormat] }].map((layout2, i2) => ({
        layout: layout2,
        reason: i2 === 0 ? null : "dateFormat",
        preview: readTable(rows2, detected.headerRow, layout2).transactions.slice(0, PREVIEW_PAYMENTS)
      }));
    }
    const { guess, columns, rows, payments: guessed } = analyseCsv(clean2);
    if (!guess.layout) return [];
    const read2 = (layout2) => {
      const start = findTable(rows, layout2);
      if (start === null) return [];
      try {
        return readTable(rows, start, layout2).transactions;
      } catch (error) {
        if (error instanceof BankFileError) return [];
        throw error;
      }
    };
    const candidates = [
      { layout: guess.layout, reason: null, payments: guessed },
      ...alternatives({ ...guess, layout: guess.layout }, columns, guessed).map((x2) => ({ ...x2, payments: read2(x2.layout) }))
    ];
    const most = Math.max(...candidates.map((x2) => x2.payments.length));
    const readings = [];
    const seen = /* @__PURE__ */ new Set();
    for (const { layout: layout2, reason, payments } of candidates) {
      if (payments.length === 0 || payments.length < most) continue;
      const preview = payments.slice(0, PREVIEW_PAYMENTS);
      const key = shown(preview);
      if (seen.has(key)) continue;
      seen.add(key);
      readings.push({ layout: layout2, reason, preview });
      if (readings.length === MAX_READINGS) break;
    }
    return readings;
  }
  function readingsOfUnknownFile(bytes, savedLayouts = []) {
    let text3;
    try {
      text3 = bankTableText(bytes, savedLayouts);
    } catch (error) {
      if (error instanceof BankFileError) return [];
      throw error;
    }
    return readingsOfUnknownText(text3, savedLayouts);
  }

  // src/engine/readers/share.ts
  var MAX_CELL = 60;
  var MAX_COLUMNS = 80;
  var MAX_BYTES = 8e3;
  var MONTH = "(jan|januar|january|feb|februar|february|m\xE4r|m\xE4rz|maerz|mar|march|apr|april|mai|may|jun|juni|june|jul|juli|july|aug|august|sep|sept|september|okt|oktober|oct|october|nov|november|dez|dezember|dec|december)\\.?(?![a-z\xE4\xF6\xFC\xDF])";
  var DATE = new RegExp(`\\d{1,4}\\s*[./-]\\s*\\d{1,2}\\s*[./-]\\s*\\d{1,4}|\\d{1,2}[\\s./-]*${MONTH}|(^|[^a-z\xE4\xF6\xFC\xDF])${MONTH}[\\s./,-]*\\d`, "i");
  var CURRENCY = "(\u20AC|\\$|\xA3|\xA5|[Ee]uro?|EURO?|[A-Z]{3})(?![A-Za-z])";
  var AMOUNT = new RegExp(`\\d\\s*[.,]\\s*\\d|\\d\\s*${CURRENCY}|(^|[^A-Za-z])${CURRENCY}\\s*\\d`);
  var DIGIT_GROUPS = /\d[\d\s./-]*\d/g;
  var digitCount = (run) => run.replace(/\D/g, "").length;
  var LOOKS_PERSONAL = [
    ["email", (t) => t.includes("@")],
    // Two letters, two check digits, then letters and digits in groups, with 8 or more digits (every country's IBAN
    // has), so that "since 2023 at Postbank" is not one.
    ["iban", (t) => (t.match(/[a-z]{2}\s?\d{2}(\s?[a-z0-9]){10,}/gi) ?? []).some((run) => digitCount(run) >= 8)],
    ["date", (t) => DATE.test(t)],
    ["amount", (t) => AMOUNT.test(t)],
    ["digits", (t) => /\d(\s?\d){4,}/.test(t) || (t.match(DIGIT_GROUPS) ?? []).some((run) => digitCount(run) >= 8)]
  ];
  function looksPersonal(text3) {
    for (const [reason, test] of LOOKS_PERSONAL) if (test(text3)) return reason;
    return text3.length > MAX_CELL ? "tooLong" : null;
  }
  function utf8Length(text3) {
    let bytes = 0;
    for (const ch of text3) {
      const code = ch.codePointAt(0);
      bytes += code < 128 ? 1 : code < 2048 ? 2 : code < 65536 ? 3 : 4;
    }
    return bytes;
  }
  var isColumn = (v) => Number.isInteger(v) && v >= 0 && v < MAX_COLUMNS;
  var isColumnList = (v) => Array.isArray(v) && v.length > 0 && v.length <= MAX_COLUMNS && v.every(isColumn);
  var isWordList = (v) => Array.isArray(v) && v.length <= MAX_COLUMNS && v.every((w) => typeof w === "string");
  var SINGLE = [
    "valueDate",
    "amount",
    "debit",
    "credit",
    "sign",
    "payer",
    "payee",
    "kind",
    "iban",
    "accountIban",
    "balance",
    "currency",
    "reference",
    "status"
  ];
  var LISTS = ["counterparty", "text", "fees", "addAmounts"];
  function shareableLayout(layout2) {
    const no = (reason) => ({ ok: false, reason });
    const input = layout2;
    if (!input || typeof input !== "object" || input.version !== 1) return no("invalid");
    const {
      separator,
      header,
      columnCount,
      dateFormat: dateFormat2,
      numberFormat,
      columns,
      skipStatus,
      keepStatus,
      invertSign,
      labelledText,
      currency
    } = input;
    if (!SEPARATORS.includes(separator) || !DATE_FORMATS.includes(dateFormat2)) return no("invalid");
    if (numberFormat !== "de" && numberFormat !== "en") return no("invalid");
    if (!Array.isArray(header) || !header.every((h) => typeof h === "string")) return no("invalid");
    if (header.length > MAX_COLUMNS) return no("tooWide");
    if (header.length === 0 && columnCount === void 0) return no("invalid");
    if (columnCount !== void 0) {
      if (!Number.isInteger(columnCount) || columnCount < 1) return no("invalid");
      if (columnCount > MAX_COLUMNS) return no("tooWide");
    }
    if (!columns || typeof columns !== "object") return no("invalid");
    const given = columns;
    if (!isColumn(given.date)) return no("invalid");
    const copy2 = { date: given.date };
    for (const role of SINGLE) {
      if (given[role] === void 0) continue;
      if (!isColumn(given[role])) return no("invalid");
      copy2[role] = given[role];
    }
    for (const role of LISTS) {
      if (given[role] === void 0) continue;
      if (!isColumnList(given[role])) return no("invalid");
      copy2[role] = [...given[role]];
    }
    if (copy2.amount === void 0 && (copy2.debit === void 0 || copy2.credit === void 0)) return no("invalid");
    for (const list2 of [skipStatus, keepStatus]) if (list2 !== void 0 && !isWordList(list2)) return no("invalid");
    let labels;
    if (labelledText !== void 0) {
      const l = labelledText;
      if (!l || typeof l !== "object" || !isWordList(l.labels) || !isWordList(l.counterparty) || !isWordList(l.text)) return no("invalid");
      labels = { labels: [...l.labels], counterparty: [...l.counterparty], text: [...l.text] };
    }
    if (currency !== void 0 && (typeof currency !== "string" || !/^[A-Z]{3}$/.test(currency))) return no("invalid");
    if (invertSign !== void 0 && typeof invertSign !== "boolean") return no("invalid");
    const words2 = [
      ...header,
      ...skipStatus ?? [],
      ...keepStatus ?? [],
      ...labels ? [...labels.labels, ...labels.counterparty, ...labels.text] : []
    ];
    for (const word of words2) {
      const reason = looksPersonal(word);
      if (reason) return no(reason);
    }
    const shared = {
      version: 1,
      separator,
      header: [...header],
      ...columnCount !== void 0 ? { columnCount } : {},
      dateFormat: dateFormat2,
      numberFormat,
      columns: copy2,
      ...skipStatus !== void 0 ? { skipStatus: [...skipStatus] } : {},
      ...keepStatus !== void 0 ? { keepStatus: [...keepStatus] } : {},
      ...invertSign === true ? { invertSign: true } : {},
      ...labels ? { labelledText: labels } : {},
      ...currency !== void 0 ? { currency } : {}
    };
    if (utf8Length(JSON.stringify(shared)) > MAX_BYTES) return no("tooLarge");
    return { ok: true, layout: shared };
  }

  // src/engine/receipts/register-code.ts
  var amount = (text3) => /^-?\d+\.\d{2}$/.test(text3) ? parseAmountStrict(text3, "en") : null;
  function readRegisterCode(code) {
    if (typeof code !== "string") return null;
    const fields2 = code.trim().split(";");
    if (fields2.length < 8 || fields2[0] !== "V0" || fields2[2] !== "Kassenbeleg-V1") return null;
    const [kind, gross, payments = ""] = fields2[3].split("^");
    if (kind !== "Beleg") return null;
    const perRate = (gross ?? "").split("_").map(amount);
    if (perRate.length !== 5) return null;
    let total = "0.00";
    for (const a of perRate) {
      if (a === null) return null;
      total = addAmounts(total, a);
    }
    let cash = false, card = false;
    for (const payment of payments ? payments.split("_") : []) {
      const [value, how] = payment.split(":");
      const paid = amount(value ?? "");
      if (paid === null || how !== "Bar" && how !== "Unbar") return null;
      if (Number(paid) <= 0) continue;
      if (how === "Bar") cash = true;
      else card = true;
    }
    const when = germanTime(fields2[7]) ?? germanTime(fields2[6]);
    return { total: Number(total), method: cash === card ? null : cash ? "cash" : "card", date: when?.date ?? null, time: when?.time ?? null };
  }
  var pad2 = (n) => String(n).padStart(2, "0");
  var lastSunday = (year, month) => {
    const last2 = new Date(Date.UTC(year, month, 0));
    return last2.getUTCDate() - last2.getUTCDay();
  };
  function germanTime(value) {
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z)?$/.exec(value?.trim() ?? "");
    if (!m) return null;
    const [y, mo, d, h, mi] = [1, 2, 3, 4, 5].map((i2) => Number(m[i2]));
    let utc = Date.UTC(y, mo - 1, d, h, mi);
    if (Number.isNaN(utc) || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
    if (m[7]) {
      const summerStart = Date.UTC(y, 2, lastSunday(y, 3), 1);
      const summerEnd = Date.UTC(y, 9, lastSunday(y, 10), 1);
      utc += (utc >= summerStart && utc < summerEnd ? 2 : 1) * 36e5;
    }
    const t = new Date(utc);
    return {
      date: `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`,
      time: `${pad2(t.getUTCHours())}:${pad2(t.getUTCMinutes())}`
    };
  }

  // src/engine/receipts/rows.ts
  var LOOK_ALIKES = {
    // Cyrillic
    \u0410: "A",
    \u0412: "B",
    \u0415: "E",
    \u041A: "K",
    \u041C: "M",
    \u041D: "H",
    \u041E: "O",
    \u0420: "P",
    \u0421: "C",
    \u0422: "T",
    \u0425: "X",
    \u0423: "Y",
    \u0406: "I",
    \u0408: "J",
    \u0405: "S",
    "\u051A": "Q",
    "\u051C": "W",
    \u0430: "a",
    \u0435: "e",
    \u043E: "o",
    \u0440: "p",
    \u0441: "c",
    \u0443: "y",
    \u0445: "x",
    \u0456: "i",
    \u0458: "j",
    \u0455: "s",
    "\u051B": "q",
    "\u051D": "w",
    \u0432: "B",
    \u043A: "K",
    \u043C: "M",
    \u043D: "H",
    \u0442: "T",
    // Greek
    \u0391: "A",
    \u0392: "B",
    \u0395: "E",
    \u0396: "Z",
    \u0397: "H",
    \u0399: "I",
    \u039A: "K",
    \u039C: "M",
    \u039D: "N",
    \u039F: "O",
    \u03A1: "P",
    \u03A4: "T",
    \u03A5: "Y",
    \u03A7: "X",
    \u03B1: "a",
    \u03B9: "i",
    \u03BA: "k",
    \u03BD: "v",
    \u03BF: "o",
    \u03C1: "p",
    \u03C5: "u",
    \u03C7: "x"
  };
  var OTHER_SCRIPT = /[\p{Script=Cyrillic}\p{Script=Greek}]/gu;
  var LATIN_OR_DIGIT = /[\p{Script=Latin}\p{N}]/gu;
  function latinLookAlikes(text3) {
    const other = text3.match(OTHER_SCRIPT)?.length ?? 0;
    if (other === 0) return text3;
    const latin = text3.match(LATIN_OR_DIGIT)?.length ?? 0;
    return text3.replace(/[\p{L}\p{N}]+/gu, (word) => {
      const mixed = /[\p{Script=Latin}\p{N}]/u.test(word);
      const single = [...word].length === 1 && latin > other;
      return mixed || single ? [...word].map((c) => LOOK_ALIKES[c] ?? c).join("") : word;
    });
  }
  var finite = (n) => typeof n === "number" && Number.isFinite(n);
  var median = (values) => {
    if (!values.length) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const mid = sorted.length >> 1;
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  };
  function slopeOf(pieces, height) {
    const slopes = [];
    for (const a of pieces) for (const b of pieces) {
      if (b.left < a.right || b.cx - a.cx < 0.05) continue;
      const dy = b.cy - a.cy;
      if (Math.abs(dy) < 0.6 * height) slopes.push(dy / (b.cx - a.cx));
    }
    return median(slopes);
  }
  function receiptRows(observations) {
    const pieces = [];
    for (const o of observations ?? []) {
      const text3 = typeof o?.text === "string" ? o.text.replace(/\s+/g, " ").trim() : "";
      if (!text3 || ![o.x, o.y, o.width, o.height].every(finite)) continue;
      pieces.push({ text: text3, left: o.x, right: o.x + o.width, cx: o.x + o.width / 2, cy: o.y + o.height / 2, height: Math.abs(o.height) });
    }
    const pages = /* @__PURE__ */ new Map();
    for (const p of pieces) {
      const page = Math.floor(p.cy);
      pages.set(page, [...pages.get(page) ?? [], p]);
    }
    const rows = [];
    for (const page of [...pages.keys()].sort((a, b) => a - b)) {
      const onPage = pages.get(page);
      const height = median(onPage.map((p) => p.height)) || 0.01;
      const slope = slopeOf(onPage, height);
      const level = (p) => p.cy - slope * p.cx;
      const ordered = [...onPage].sort((a, b) => level(a) - level(b) || a.left - b.left);
      const lines = [];
      for (const p of ordered) {
        const line = lines.at(-1);
        const overlaps = line?.pieces.some((q) => Math.min(q.right, p.right) - Math.max(q.left, p.left) > 0.3 * Math.min(q.right - q.left, p.right - p.left));
        if (line && Math.abs(level(p) - line.y) <= 0.5 * height && !overlaps) {
          line.pieces.push(p);
          line.y = line.pieces.reduce((sum, q) => sum + level(q), 0) / line.pieces.length;
        } else {
          lines.push({ y: level(p), pieces: [p] });
        }
      }
      for (const line of lines) rows.push(latinLookAlikes(line.pieces.sort((a, b) => a.left - b.left).map((p) => p.text).join(" ")));
    }
    return rows;
  }

  // src/engine/receipts/words.ts
  var RECEIPT_WORDS = {
    de: {
      due: ["zu zahlen", "zahlbetrag", "zu zahlender betrag"],
      total: ["summe", "gesamt", "gesamtbetrag", "gesamtsumme", "endsumme", "endbetrag", "bonsumme", "rechnungsbetrag", "summe eur"],
      amount: ["betrag"],
      subtotal: ["zwischensumme", "zw summe", "zwsumme"],
      tax: ["mwst", "ust", "steuer", "netto", "brutto", "nettobetrag", "steuerbetrag", "mehrwertsteuer", "umsatzsteuer", "mwst satz", "steuersatz"],
      deposit: ["pfand", "leergut", "pfandr\xFCckgabe", "pfandbon", "leergutbon", "pfandgutschrift", "flaschenpfand"],
      tip: ["trinkgeld"],
      other: ["rabatt", "ersparnis", "gespart", "sie sparen", "nachlass", "payback", "punkte", "gutschein"],
      card: ["karte", "kartenzahlung", "girocard", "ec karte", "ec cash", "ec", "kreditkarte", "debitkarte", "kontaktlos", "bankkarte", "electronic cash", "elv"],
      cash: ["bar", "barzahlung", "bargeld", "in bar"],
      given: ["gegeben", "geg", "erhalten"],
      change: ["r\xFCckgeld", "zur\xFCck", "wechselgeld"],
      register: ["kasse", "kassierer", "kassiererin", "bediener", "bon", "bon nr", "bonnr", "beleg", "beleg nr", "belegnr", "filiale", "tse", "transaktion", "seriennummer", "signatur", "signaturz\xE4hler", "terminal", "trace", "kassenbon", "quittung", "rechnung", "kundenbeleg", "h\xE4ndlerbeleg", "ust id", "ust idnr", "st nr", "steuernummer", "steuer nr", "uid", "uid nr", "inh", "inhaber"],
      greeting: ["willkommen", "danke", "vielen dank", "auf wiedersehen", "bis bald", "ihr einkauf"],
      street: ["stra\xDFe", "str", "weg", "platz", "allee", "gasse", "ring", "damm", "chaussee", "ufer"],
      phone: ["tel", "telefon", "fon", "fax"],
      date: ["datum"],
      validity: ["g\xFCltig", "g\xFCltig bis", "bis", "mhd", "haltbar", "ablauf", "einl\xF6sbar"]
    },
    en: {
      due: ["amount due", "balance due", "total due", "to pay", "total to pay", "amount to pay"],
      total: ["total", "grand total", "total gbp", "total usd"],
      amount: ["amount", "purchase", "sale"],
      subtotal: ["subtotal", "sub total"],
      tax: ["vat", "tax", "sales tax", "net", "excl vat", "incl vat", "vat rate", "gst", "hst"],
      deposit: ["deposit", "bottle deposit", "bottle return"],
      tip: ["tip", "gratuity", "service charge"],
      other: ["savings", "you saved", "saved", "discount", "points", "clubcard", "nectar"],
      card: ["card", "debit", "credit", "chip", "debit card", "credit card", "card payment"],
      cash: ["cash"],
      given: ["tendered", "cash tendered", "tender", "given"],
      change: ["change", "change due"],
      register: ["till", "cashier", "operator", "receipt", "receipt no", "terminal", "transaction", "trans", "auth code", "vat no", "vat reg", "store no"],
      greeting: ["welcome", "thank you", "thanks", "see you"],
      street: ["street", "st", "road", "rd", "avenue", "ave", "lane", "way", "square", "blvd", "boulevard", "drive"],
      phone: ["tel", "phone", "telephone"],
      date: ["date"],
      validity: ["valid", "valid until", "until", "expires", "exp"]
    },
    fr: {
      due: ["net \xE0 payer", "\xE0 payer", "total \xE0 payer", "montant d\xFB"],
      total: ["total", "total ttc", "montant ttc", "total eur"],
      amount: ["montant"],
      subtotal: ["sous total"],
      tax: ["tva", "ht", "total ht", "total tva", "montant ht", "taux", "montant tva"],
      deposit: ["consigne"],
      tip: ["pourboire"],
      other: ["remise", "\xE9conomie", "\xE9conomies", "r\xE9duction", "points", "fid\xE9lit\xE9"],
      card: ["carte", "cb", "carte bancaire", "carte bleue", "sans contact", "paiement carte", "carte cr\xE9dit"],
      cash: ["esp\xE8ces", "en esp\xE8ces", "liquide"],
      given: ["re\xE7u", "esp\xE8ces re\xE7ues", "donn\xE9", "montant re\xE7u"],
      change: ["rendu", "monnaie rendue", "\xE0 rendre", "rendu monnaie", "monnaie"],
      register: ["caisse", "caissier", "caissi\xE8re", "ticket", "facture", "terminal", "transaction", "siret", "siren", "n tva"],
      greeting: ["bienvenue", "merci", "\xE0 bient\xF4t", "au revoir"],
      street: ["rue", "avenue", "av", "boulevard", "bd", "place", "chemin", "all\xE9e", "quai", "impasse", "route"],
      phone: ["t\xE9l", "tel", "t\xE9l\xE9phone"],
      date: ["date"],
      validity: ["valable", "jusqu", "expire"]
    },
    it: {
      due: ["da pagare", "totale da pagare", "importo pagato"],
      total: ["totale", "totale complessivo", "totale euro"],
      amount: ["importo"],
      subtotal: ["subtotale", "sub totale"],
      tax: ["iva", "imponibile", "di cui iva", "imposta", "aliquota"],
      deposit: ["vuoto", "cauzione"],
      tip: ["mancia"],
      other: ["sconto", "risparmio", "punti"],
      card: ["carta", "bancomat", "pagobancomat", "carta di credito", "carta di debito", "pagamento elettronico", "elettronico"],
      cash: ["contanti", "contante", "pagamento contante"],
      given: ["ricevuto", "contante ricevuto", "pagato"],
      change: ["resto"],
      register: ["cassa", "cassiere", "scontrino", "documento commerciale", "ricevuta", "doc n", "partita iva", "p iva", "matricola", "terminale"],
      greeting: ["benvenuti", "grazie", "arrivederci"],
      street: ["via", "viale", "piazza", "corso", "largo", "vicolo", "strada"],
      phone: ["tel", "telefono"],
      date: ["data"],
      validity: ["valido", "scadenza", "fino"]
    },
    es: {
      due: ["a pagar", "total a pagar"],
      total: ["total", "importe total", "total eur"],
      amount: ["importe"],
      subtotal: ["subtotal", "sub total"],
      tax: ["iva", "base imponible", "base", "cuota", "impuestos", "igic"],
      deposit: ["envase"],
      tip: ["propina"],
      other: ["descuento", "ahorro", "puntos"],
      card: ["tarjeta", "tarjeta cr\xE9dito", "tarjeta d\xE9bito", "pago con tarjeta", "sin contacto", "dat\xE1fono"],
      cash: ["efectivo", "met\xE1lico", "en efectivo", "contado"],
      given: ["entregado", "recibido", "efectivo entregado", "entrega"],
      change: ["cambio", "vuelto", "su cambio", "a devolver"],
      register: ["caja", "cajero", "cajera", "ticket", "factura", "factura simplificada", "nif", "cif", "terminal", "operaci\xF3n"],
      greeting: ["bienvenido", "gracias", "hasta pronto"],
      street: ["calle", "c", "avenida", "avda", "plaza", "paseo", "carretera", "camino"],
      phone: ["tel", "tel\xE9fono", "tfno"],
      date: ["fecha"],
      validity: ["v\xE1lido", "hasta", "caduca"]
    },
    nl: {
      due: ["te betalen", "totaal te betalen"],
      total: ["totaal", "totaal bedrag", "eindtotaal"],
      amount: ["bedrag"],
      subtotal: ["subtotaal"],
      tax: ["btw", "excl btw", "incl btw", "netto", "grondslag"],
      deposit: ["statiegeld", "emballage", "leeggoed"],
      tip: ["fooi"],
      other: ["korting", "voordeel", "bespaard", "punten"],
      card: ["pin", "pinnen", "gepind", "pinbetaling", "betaalkaart", "bankpas", "contactloos", "creditcard"],
      cash: ["contant", "contanten", "contant betaald"],
      given: ["ontvangen", "betaald"],
      change: ["wisselgeld", "terug", "retour"],
      register: ["kassa", "kassabon", "bon", "bon nr", "caissi\xE8re", "medewerker", "terminal", "transactie", "kvk", "btw nr"],
      greeting: ["welkom", "bedankt", "dank u", "tot ziens"],
      street: ["straat", "laan", "weg", "plein", "gracht", "kade", "singel", "dijk"],
      phone: ["tel", "telefoon"],
      date: ["datum"],
      validity: ["geldig", "tot"]
    },
    pt: {
      due: ["a pagar", "total a pagar"],
      total: ["total", "valor total", "total eur"],
      amount: ["valor"],
      subtotal: ["subtotal"],
      tax: ["iva", "taxa", "base tribut\xE1vel", "incid\xEAncia", "valor iva"],
      deposit: ["tara", "vasilhame"],
      tip: ["gorjeta"],
      other: ["desconto", "poupan\xE7a", "pontos"],
      card: ["cart\xE3o", "multibanco", "mb", "cart\xE3o cr\xE9dito", "cart\xE3o d\xE9bito", "d\xE9bito", "cr\xE9dito", "mb way", "tpa"],
      cash: ["dinheiro", "numer\xE1rio", "em dinheiro"],
      given: ["entregue", "recebido", "valor entregue", "valor recebido"],
      change: ["troco"],
      register: ["caixa", "operador", "fatura", "fatura simplificada", "fatura recibo", "nif", "contribuinte", "atcud", "tal\xE3o", "terminal"],
      greeting: ["bem vindo", "obrigado", "obrigada", "volte sempre"],
      street: ["rua", "avenida", "av", "pra\xE7a", "largo", "travessa", "estrada", "alameda"],
      phone: ["tel", "telefone"],
      date: ["data"],
      validity: ["v\xE1lido", "at\xE9", "validade"]
    }
  };
  var SHARED_WORDS = {
    card: [
      "visa",
      "mastercard",
      "master card",
      "maestro",
      "v pay",
      "vpay",
      "amex",
      "american express",
      "apple pay",
      "google pay",
      "jcb",
      "unionpay",
      "diners",
      "visa debit",
      "debit mastercard",
      "contactless"
    ],
    other: ["coupon"]
  };
  var STREET_ENDINGS = ["strasse", "str", "weg", "platz", "allee", "gasse", "ring", "damm", "straat", "laan", "plein", "gracht", "kade", "dijk", "singel"];
  var FUZZY_KINDS = ["due", "total"];
  var FUZZY_MIN_LENGTH = 5;
  var ISO_CURRENCIES = [
    "EUR",
    "GBP",
    "USD",
    "CHF",
    "SEK",
    "NOK",
    "DKK",
    "PLN",
    "CZK",
    "HUF",
    "RON",
    "BGN",
    "JPY",
    "CAD",
    "AUD",
    "BRL",
    "ISK"
  ];
  var CURRENCY_SIGNS = [
    ["US$", "USD"],
    ["CA$", "CAD"],
    ["C$", "CAD"],
    ["AU$", "AUD"],
    ["A$", "AUD"],
    ["R$", "BRL"],
    ["\u20AC", "EUR"],
    ["\xA3", "GBP"],
    ["$", "USD"],
    ["SFr.", "CHF"],
    ["Fr.", "CHF"],
    ["Fr", "CHF"],
    ["z\u0142", "PLN"],
    ["K\u010D", "CZK"],
    ["Ft", "HUF"],
    ["lei", "RON"],
    ["\u043B\u0432", "BGN"],
    ["\u20BA", "TRY"],
    ["TL", "TRY"],
    ["\xA5", "JPY"],
    ["\u20B9", "INR"],
    ["kr", "kr"]
  ];
  var KRONE_BY_PHONE = { "+45": "DKK", "+46": "SEK", "+47": "NOK", "+354": "ISK" };

  // src/engine/receipts/read.ts
  var phrasesOf = (table, language) => Object.entries(table).flatMap(([kind, list2]) => (list2 ?? []).map((text3) => ({ words: shopWords(text3), kind, language })));
  var PHRASES = [
    ...Object.entries(RECEIPT_WORDS).flatMap(([language, table]) => phrasesOf(table, language)),
    ...phrasesOf(SHARED_WORDS, null)
  ].filter((p) => p.words.length > 0);
  var BY_FIRST_WORD = /* @__PURE__ */ new Map();
  for (const p of PHRASES) BY_FIRST_WORD.set(p.words[0], [...BY_FIRST_WORD.get(p.words[0]) ?? [], p]);
  var FUZZY = PHRASES.filter((p) => p.words.length === 1 && FUZZY_KINDS.includes(p.kind) && p.words[0].length >= FUZZY_MIN_LENGTH);
  var LANGUAGES = Object.keys(RECEIPT_WORDS);
  function nearlySame(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false;
    let i2 = 0, j = 0, edits = 0;
    while (i2 < a.length && j < b.length) {
      if (a[i2] === b[j]) {
        i2++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) i2++;
      else if (b.length > a.length) j++;
      else {
        i2++;
        j++;
      }
    }
    return edits + (a.length - i2) + (b.length - j) <= 1;
  }
  function hitsIn(words2) {
    const hits = [];
    for (let start = 0; start < words2.length; start++) {
      for (const p of BY_FIRST_WORD.get(words2[start]) ?? []) {
        const end = start + p.words.length;
        if (end <= words2.length && p.words.every((w, k) => words2[start + k] === w)) {
          hits.push({ start, end, kind: p.kind, language: p.language, fuzzy: false, phrase: p.words.join(" ") });
        }
      }
    }
    words2.forEach((word, i2) => {
      if (word.length < FUZZY_MIN_LENGTH - 1 || !/\p{L}/u.test(word) || hits.some((h) => h.start <= i2 && i2 < h.end)) return;
      for (const p of FUZZY) {
        if (nearlySame(word, p.words[0])) hits.push({ start: i2, end: i2 + 1, kind: p.kind, language: p.language, fuzzy: true, phrase: p.words[0] });
      }
    });
    return hits.filter((h) => !hits.some((o) => o.start <= h.start && o.end >= h.end && o.end - o.start > h.end - h.start));
  }
  var AMOUNT2 = /(?<![\p{L}\p{N}.,'])([-−–]\s?)?(?:US\$|CA\$|AU\$|R\$|[€£$]|EUR|CHF|GBP|USD)?\s?(\d{1,3}(?:[.,']\d{3})+|\d+)([.,])(\d{2})(?![\p{N}]|[.,]\d)(\s?[-−])?/gu;
  var PRICE_WITH_OS = /^([-−]?[€£$]?)([\dOo]+(?:[.,'][\dOo]{3})*[.,][\dOo]{2})([-−]?[A-Z€£$]?)$/;
  var zeroes = (text3) => text3.split(/(\s+)/).map((piece) => {
    const m = PRICE_WITH_OS.exec(piece);
    return m && /\d/.test(m[2]) ? m[1] + m[2].replace(/[Oo]/g, "0") + m[3] : piece;
  }).join("");
  function amountsIn(raw) {
    const text3 = zeroes(raw).replace(/’/g, "'").replace(/(\d)\s*[xX*]\s*(\d)/g, "$1 x $2");
    const amounts = [];
    for (const m of text3.matchAll(AMOUNT2)) {
      const after = text3.slice(m.index + m[0].length);
      if (/^\s?(?:%|uhr\b|h\b)/iu.test(after)) continue;
      const value = parseAmountStrict(`${(m[1] ?? "").trim()}${m[2]}${m[3]}${m[4]}${(m[5] ?? "").trim()}`, m[3] === "," ? "de" : "en");
      if (value !== null) amounts.push(Number(value));
    }
    return amounts;
  }
  var MONTH_NAMES = [
    ["january", "januar", "janvier", "gennaio", "enero", "januari", "janeiro", "jaenner"],
    ["february", "februar", "fevrier", "febbraio", "febrero", "februari", "fevereiro"],
    ["march", "maerz", "mars", "marzo", "maart", "marco", "mrt"],
    ["april", "avril", "aprile", "abril"],
    ["may", "mai", "maggio", "mayo", "mei", "maio"],
    ["june", "juni", "juin", "giugno", "junio", "junho"],
    ["july", "juli", "juillet", "luglio", "julio", "julho"],
    ["august", "aout", "agosto", "augustus"],
    ["september", "septembre", "settembre", "septiembre", "setembro"],
    ["october", "oktober", "octobre", "ottobre", "octubre", "outubro"],
    ["november", "novembre", "noviembre", "novembro"],
    ["december", "dezember", "decembre", "dicembre", "diciembre", "dezembro"]
  ];
  var monthOf = (word) => {
    const w = shopWords(word)[0] ?? "";
    if (w.length < 3) return null;
    const index = MONTH_NAMES.findIndex((names2) => names2.some((name) => name.startsWith(w)));
    return index < 0 ? null : index + 1;
  };
  var fullYear2 = (y) => y.length === 2 ? `20${y}` : y;
  function datesIn(text3, monthFirst) {
    const found = [];
    for (const m of text3.matchAll(/(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(T\d)?(?!\d)/g)) {
      const day2 = parseDate(`${m[1]}-${m[2]}-${m[3]}`, "YYYY-MM-DD");
      if (day2) found.push({ day: day2, ambiguous: false, utc: !!m[4] });
    }
    for (const m of text3.matchAll(/(?<![\d./-])(\d{1,2})([./-])(\d{1,2})\2(\d{4}|\d{2})(?![\d.]\d|\d)/g)) {
      const year = fullYear2(m[4]);
      const dayFirst = parseDate(`${m[1]}.${m[3]}.${year}`, "DD.MM.YYYY");
      if (m[2] === ".") {
        if (dayFirst) found.push({ day: dayFirst, ambiguous: false, utc: false });
        continue;
      }
      const monthFirstDay = parseDate(`${m[1]}/${m[3]}/${year}`, "MM/DD/YYYY");
      const day2 = monthFirst ? monthFirstDay ?? dayFirst : dayFirst ?? monthFirstDay;
      if (day2) found.push({ day: day2, ambiguous: !!dayFirst && !!monthFirstDay && dayFirst !== monthFirstDay, utc: false });
    }
    const named = [
      { re: /(?<!\d)(\d{1,2})\.?\s*(?:de\s+)?(\p{L}{3,})\.?,?\s*(?:de\s+)?(\d{4})(?!\d)/gu, d: 1, mo: 2, y: 3 },
      { re: /(?<!\p{L})(\p{L}{3,})\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)/gu, d: 2, mo: 1, y: 3 }
    ];
    for (const { re, d, mo, y } of named) {
      for (const m of text3.matchAll(re)) {
        const month = monthOf(m[mo]);
        const day2 = month && parseDate(`${m[d]}.${month}.${m[y]}`, "DD.MM.YYYY");
        if (day2) found.push({ day: day2, ambiguous: false, utc: false });
      }
    }
    return found;
  }
  var pad3 = (n) => String(n).padStart(2, "0");
  function timesIn(text3) {
    const times = [];
    for (const m of text3.matchAll(/(?<![\d:.])(\d{1,2})(?::|h)(\d{2})(?::\d{2})?(?![\d])(?:\s*([ap])\.?\s?m\b\.?)?/giu)) {
      let hour = Number(m[1]);
      const minute = Number(m[2]);
      if (minute > 59) continue;
      if (m[3]) {
        if (hour < 1 || hour > 12) continue;
        hour = hour % 12 + (m[3].toLowerCase() === "p" ? 12 : 0);
      } else if (hour > 23) continue;
      times.push(`${pad3(hour)}:${pad3(minute)}`);
    }
    return times;
  }
  var has = (line, ...kinds) => kinds.some((k) => line.kinds.has(k));
  var last = (line) => line.amounts.at(-1) ?? null;
  var cents4 = (n) => Math.round(n * 100);
  function readLine(text3, index, monthFirst) {
    const words2 = shopWords(text3);
    const hits = hitsIn(words2);
    const dates = datesIn(text3, monthFirst);
    const times = timesIn(text3);
    const amounts = dates.length ? [] : amountsIn(text3);
    return { index, text: text3, words: words2, hits, kinds: new Set(hits.map((h) => h.kind)), amounts, dates, times };
  }
  var SIGNS = CURRENCY_SIGNS.map(([sign, code]) => {
    const escaped = sign.replace(/[.$]/g, "\\$&");
    return { code, re: new RegExp(/^\p{L}/u.test(sign) ? `(?<![\\p{L}])${escaped}(?![\\p{L}])` : escaped, "gu") };
  });
  function currencyOf(lines, totalLine) {
    const votes = /* @__PURE__ */ new Map();
    const vote = (code, weight) => votes.set(code, (votes.get(code) ?? 0) + weight);
    for (const line of lines) {
      const weight = line === totalLine ? 3 : 1;
      for (const code of line.text.match(/(?<![\p{L}])[A-Z]{3}(?![\p{L}])/gu) ?? []) if (ISO_CURRENCIES.includes(code)) vote(code, weight);
      if (!line.amounts.length) continue;
      let rest = line.text;
      for (const { code, re } of SIGNS) {
        const without = rest.replace(re, " ");
        if (without !== rest) {
          vote(code, weight);
          rest = without;
        }
      }
    }
    if (votes.size === 0) return "EUR";
    const [best] = [...votes].sort((a, b) => b[1] - a[1]);
    if (best[0] !== "kr") return best[0];
    const iso = ["SEK", "NOK", "DKK", "ISK"].find((code) => votes.has(code));
    if (iso) return iso;
    const all = lines.map((l) => l.text).join(" ");
    const phone = Object.keys(KRONE_BY_PHONE).find((prefix) => all.includes(prefix));
    return phone ? KRONE_BY_PHONE[phone] : null;
  }
  function languageOf(lines, currency) {
    const score = /* @__PURE__ */ new Map();
    for (const line of lines) for (const h of line.hits) {
      if (h.language) score.set(h.language, (score.get(h.language) ?? /* @__PURE__ */ new Set()).add(h.phrase));
    }
    let best = null, bestScore = 0;
    for (const language of LANGUAGES) {
      const s = (score.get(language)?.size ?? 0) + (language === "en" && (currency === "GBP" || currency === "USD") ? 0.5 : 0);
      if (s > bestScore) {
        best = language;
        bestScore = s;
      }
    }
    return score.size ? best : null;
  }
  var STRENGTH = { due: 3, total: 2, amount: 1 };
  var TOTAL_KINDS = ["due", "total", "amount"];
  var NEVER_TOTAL = ["subtotal", "tax", "deposit", "tip", "other", "given", "change"];
  function totalOf(lines) {
    const candidates = [];
    for (const line of lines) {
      const amount2 = last(line);
      if (amount2 === null || amount2 <= 0 || has(line, ...NEVER_TOTAL)) continue;
      const totalHits = line.hits.filter((h) => STRENGTH[h.kind]);
      if (!totalHits.length) continue;
      const strength = Math.max(...totalHits.map((h) => STRENGTH[h.kind]));
      candidates.push({ line, amount: amount2, strength, fuzzy: totalHits.every((h) => h.fuzzy) });
    }
    const paying = candidates.length ? lines.slice(candidates[0].line.index) : lines;
    const given = paying.find((l) => has(l, "given") && !has(l, "change", "card") && (last(l) ?? 0) > 0) ?? paying.find((l) => has(l, "cash") && !has(l, "card", "change", ...TOTAL_KINDS) && (last(l) ?? 0) > 0);
    const change = paying.find((l) => has(l, "change") && !has(l, "deposit") && last(l) !== null && last(l) >= 0);
    const byChange = given && change ? (cents4(last(given)) - cents4(last(change))) / 100 : null;
    const tips = lines.filter((l) => has(l, "tip") && (last(l) ?? 0) > 0).map((l) => last(l));
    if (candidates.length) {
      const top = Math.max(...candidates.map((c) => c.strength));
      const best = candidates.filter((c) => c.strength === top);
      const amounts = [...new Set(best.map((c) => cents4(c.amount)))];
      const confirmed = (c) => byChange !== null && cents4(c.amount) === cents4(byChange);
      let pick2, sure;
      if (amounts.length === 1) {
        pick2 = best.find((c) => !c.fuzzy) ?? best[0];
        sure = !pick2.fuzzy || confirmed(pick2);
      } else {
        const byTip = best.find((b) => best.some((a) => tips.some((t) => cents4(a.amount) + cents4(t) === cents4(b.amount))));
        const explained = byTip ?? best.find(confirmed);
        pick2 = explained ?? best.at(-1);
        sure = !!explained && (!pick2.fuzzy || confirmed(pick2));
      }
      if (byChange !== null && !confirmed(pick2)) sure = false;
      return { total: pick2.amount, sure, line: pick2.line, first: candidates[0].line };
    }
    const plain2 = lines.filter((l) => !has(l, "given", "change", "tax", "other", "deposit", "tip") && (last(l) ?? 0) > 0);
    const confirmedLine = byChange !== null && byChange > 0 ? plain2.find((l) => l.amounts.some((a) => cents4(a) === cents4(byChange))) : void 0;
    if (confirmedLine) return { total: byChange, sure: false, line: confirmedLine, first: null };
    let largest = null;
    for (const l of plain2) if (!largest || last(l) > last(largest)) largest = l;
    return { total: largest ? last(largest) : null, sure: false, line: largest, first: null };
  }
  function methodOf(lines) {
    const card = lines.some((l) => has(l, "card") && !has(l, "other", "deposit"));
    const cash = lines.some((l) => !has(l, "card", "deposit") && (last(l) ?? 0) > 0 && has(l, "cash", "given", "change"));
    return card === cash ? null : card ? "card" : "cash";
  }
  function dateOf(lines) {
    let best = null;
    const all = [];
    for (const line2 of lines) for (const hit2 of line2.dates) {
      const utc = hit2.utc || line2.words.includes("tse");
      const score = (line2.times.length ? 2 : 0) + (has(line2, "date") ? 1 : 0) - (has(line2, "validity") ? 3 : 0) - (utc ? 1 : 0);
      all.push({ hit: hit2, score, utc });
      if (!best || score > best.score) best = { line: line2, hit: hit2, score };
    }
    if (!best) return { date: null, time: null, sure: false };
    const { line, hit } = best;
    const near = [line, lines[line.index + 1], lines[line.index - 1]].filter(Boolean);
    const time = near.find((l) => l.times.length)?.times[0] ?? null;
    const others = all.filter((d) => d.score >= 0 && !d.utc && d.hit.day !== hit.day);
    return { date: hit.day, time, sure: !hit.ambiguous && others.length === 0 };
  }
  var WEB = /https?:|www\.|@|\.(?:de|com|fr|it|es|nl|pt|ch|at|be|uk)\b/i;
  function isAddress(line) {
    const t = line.text;
    if (/\d/.test(t) && (has(line, "street") || line.words.some((w) => STREET_ENDINGS.some((e) => w.length > e.length + 2 && w.endsWith(e))))) return true;
    return /\b\d{4,5}\s+\p{L}{2,}/u.test(t) || /\b\d{4}-\d{3}\b/.test(t) || /\b\d{4}\s?[A-Z]{2}\b/.test(t) || /\b[A-Z]{1,2}\d[A-Z\d]?\s\d[A-Z]{2}\b/.test(t) || /\b[A-Z]{2}\s\d{5}(?:-\d{4})?\b/.test(t);
  }
  function isNameLine(line) {
    const letters = (line.text.match(/\p{L}/gu) ?? []).length;
    const digits = (line.text.match(/\p{N}/gu) ?? []).length;
    if (letters < 2 || digits > letters || line.amounts.length || line.dates.length || line.times.length) return false;
    if (has(line, "due", "total", "amount", "subtotal", "tax", "card", "cash", "given", "change", "register", "greeting", "phone", "date", "validity")) return false;
    return !isAddress(line) && !WEB.test(line.text) && !/\b[A-Z]{2}\s?\d{8,12}\b/.test(line.text) && !/\d[\d\s/-]{5,}\d/.test(line.text);
  }
  function printedWords(text3) {
    const tokens = [...text3.normalize("NFC").matchAll(/[\p{L}\p{M}\p{N}'’‘`´]+|[&+]/gu)].filter((m) => shopWords(m[0]).length === 1);
    return tokens.length === shopWords(text3).length ? tokens.map((m) => ({ index: m.index, end: m.index + m[0].length })) : null;
  }
  var chainLike = (found) => found.source !== "rule" || found.direction === "both";
  var clean = (text3) => text3.replace(/\s+/g, " ").replace(/^[\s*#.,:;|-]+|[\s*#,:;|-]+$/g, "");
  function shopIn(text3, found, whole) {
    if (whole && !chainLike(found)) return clean(text3);
    const spans = found.at && printedWords(text3);
    if (!spans || !found.at) return clean(text3);
    return clean(text3.slice(spans[found.at[0]].index, spans[found.at[1] - 1].end));
  }
  function shopOf(lines, itemsFrom, itemsTo) {
    const find = (text3) => findShop({ counterparty: text3, amount: -1 });
    const top = lines.slice(0, Math.min(itemsFrom, 10)).filter((l) => !l.amounts.length && !l.dates.length && !l.times.length && !isAddress(l) && !WEB.test(l.text));
    for (const line of top) {
      const found = find(line.text);
      if (found && (chainLike(found) || isNameLine(line))) return { shop: shopIn(line.text, found, true), categoryId: found.categoryId, sure: true };
    }
    const header = top.filter(isNameLine);
    if (header.length) {
      const first = header[0].text.split(/\s+/)[0];
      const found = first ? find(first) : null;
      if (found && chainLike(found)) return { shop: clean(first), categoryId: found.categoryId, sure: true };
    }
    for (const line of lines) {
      if (line.index >= itemsFrom && line.index < itemsTo || has(line, "due", "total", "amount", "card", "cash", "given", "change")) continue;
      const found = find(line.text);
      if (found && chainLike(found)) return { shop: shopIn(line.text, found, false), categoryId: found.categoryId, sure: true };
    }
    return header.length ? { shop: clean(header[0].text), categoryId: null, sure: false } : { shop: null, categoryId: null, sure: false };
  }
  function readReceipt(input) {
    const rows = receiptRows(input?.observations ?? []);
    const firstPass = rows.map((text3, i2) => readLine(text3, i2, false));
    const dollars = currencyOf(firstPass, null) === "USD";
    const lines = dollars ? rows.map((text3, i2) => readLine(text3, i2, true)) : firstPass;
    const total = totalOf(lines);
    const currency = currencyOf(lines, total.line);
    const firstAmount = lines.findIndex((l) => l.amounts.length > 0);
    const itemsFrom = firstAmount < 0 ? lines.length : firstAmount;
    const itemsTo = total.first?.index ?? total.line?.index ?? lines.length;
    const payment = lines.slice(total.first?.index ?? 0);
    const method = methodOf(payment);
    const date2 = dateOf(lines);
    const shop = shopOf(lines, itemsFrom, itemsTo);
    const reading = {
      shop: shop.shop,
      categoryId: shop.categoryId,
      date: date2.date,
      time: date2.time,
      total: total.total,
      currency,
      method,
      language: languageOf(lines, currency),
      from: "text",
      rows,
      sure: { shop: shop.sure, date: date2.sure, total: total.sure, method: method !== null }
    };
    const code = (input?.codes ?? []).map(readRegisterCode).find((c) => c !== null);
    if (!code) return reading;
    return {
      ...reading,
      from: "code",
      total: code.total,
      currency: "EUR",
      method: code.method ?? reading.method,
      date: code.date ?? reading.date,
      time: code.date ? code.time : reading.time,
      sure: { shop: shop.sure, date: code.date ? true : date2.sure, total: true, method: code.method !== null }
    };
  }

  // src/engine/receipts/match.ts
  var WINDOW_DAYS = 7;
  var MORE_AT_MOST = 2e4;
  var LESS_UNDER = 0.02;
  var MAX_CANDIDATES = 5;
  var PROCESSORS = [
    "sumup",
    "zettle",
    "izettle",
    "sq",
    "stripe",
    "adyen",
    "worldline",
    "nexi",
    "concardis",
    "payone",
    "elavon",
    "telecash",
    "ingenico",
    "mollie",
    "klarna",
    "paypal",
    "ccv",
    "unzer",
    "computop",
    "fiserv",
    "vr payment",
    "global payments",
    "first data",
    "viva wallet",
    "apple pay",
    "google pay"
  ].map((name) => name.split(" "));
  var BOOKING = /* @__PURE__ */ new Set([
    "girocard",
    "debitkarte",
    "debitk",
    "kreditkarte",
    "visa",
    "mastercard",
    "maestro",
    "vpay",
    "kontaktlos",
    "contactless",
    "karte",
    "card",
    "pos",
    "nfc",
    "kartenzahlung",
    "zahlung",
    "kaufumsatz",
    "terminal",
    "kfn",
    "uhr",
    "datum",
    "deu"
  ]);
  var FILLERS = /* @__PURE__ */ new Set([
    "markt",
    "filiale",
    "store",
    "shop",
    "gmbh",
    "ltd",
    "inc",
    "llc",
    "sa",
    "sl",
    "srl",
    "spa",
    "bv",
    "nv",
    "lda",
    "sas",
    "sarl",
    "und",
    "and",
    "the",
    "der",
    "die",
    "das",
    "le",
    "la",
    "il",
    "el",
    "de",
    "da",
    "di",
    "do",
    "van"
  ]);
  var chainLike2 = (found) => !!found && (found.source !== "rule" || found.direction === "both");
  var generic = (word) => {
    const found = findShop({ counterparty: word, amount: -1 });
    return !!found && !chainLike2(found);
  };
  var nameWords = (words2, drop) => words2.filter((w) => w.length >= 3 && !/^\d+$/.test(w) && !drop(w));
  function withoutProcessors(words2) {
    const kept = [];
    for (let i2 = 0; i2 < words2.length; ) {
      const name = PROCESSORS.find((p) => p.every((w, k) => words2[i2 + k] === w));
      if (name) i2 += name.length;
      else kept.push(words2[i2++]);
    }
    return kept;
  }
  var sameWord = (a, b) => a === b || Math.min(a.length, b.length) >= 4 && (a.startsWith(b) || b.startsWith(a));
  function receiptShop(shop) {
    if (!shop?.trim()) return null;
    const receipt = { counterparty: shop, amount: -1 };
    const found = findShop(receipt);
    const key = merchantKey(receipt);
    return { chain: chainLike2(found) ? found : null, key, words: nameWords(shopWords(key), (w) => FILLERS.has(w) || generic(w)) };
  }
  function sameShop(shop, payment) {
    if (!shop) return "unknown";
    const bank = { counterparty: payment.counterparty ?? null, description: payment.description ?? "", amount: payment.amount };
    const theirs = findShop(bank);
    if (shop.chain && chainLike2(theirs)) {
      const a = shop.chain.name.split(" "), b = theirs.name.split(" ");
      return a.every((w, i2) => b[i2] === void 0 || b[i2] === w) || b.every((w, i2) => a[i2] === void 0 || a[i2] === w) ? "similar" : "different";
    }
    if (shop.key && shop.key === merchantKey(bank)) return "similar";
    const bankWords = nameWords(withoutProcessors(shopWords(merchantKey(bank))), (w) => BOOKING.has(w));
    if (!bankWords.length || !shop.words.length) return "unknown";
    return shop.words.every((w) => bankWords.some((b) => sameWord(w, b))) ? "similar" : "different";
  }
  var cents5 = (n) => Math.round(n * 100);
  var currencyOf2 = (code) => (code?.trim() || "EUR").toUpperCase();
  function matchReceipt(receipt, payments, taken = []) {
    const day2 = parseDay(receipt?.date);
    const total = receipt?.total;
    if (!day2 || typeof total !== "number" || !Number.isFinite(total) || total <= 0) return { exact: null, candidates: [] };
    const used = new Set(taken);
    const currency = currencyOf2(receipt.currency);
    const shopOfReceipt = receiptShop(receipt.shop);
    const exact = [], differs = [], other = [];
    for (const payment of payments ?? []) {
      const booked = parseDay(payment?.date);
      if (!booked || used.has(payment.id) || typeof payment.amount !== "number" || !(payment.amount < 0)) continue;
      const days = dayNumber(booked) - dayNumber(day2);
      if (days < 0 || days > WINDOW_DAYS) continue;
      const shop = sameShop(shopOfReceipt, payment);
      if (shop === "different") continue;
      if (currencyOf2(payment.currency) !== currency) {
        if (shop === "similar") other.push({ id: payment.id, why: "otherCurrency", days, difference: null, shop });
        continue;
      }
      const difference = cents5(-payment.amount) - cents5(total);
      if (difference === 0) exact.push({ id: payment.id, why: "severalSame", days, difference: 0, shop });
      else if (shop === "similar" && (difference > 0 ? difference <= MORE_AT_MOST : -difference < LESS_UNDER * cents5(total))) {
        differs.push({ id: payment.id, why: "amountDiffers", days, difference: difference / 100, shop });
      }
    }
    if (exact.length === 1) return { exact: exact[0].id, candidates: [] };
    const nearer = (a, b) => a.days - b.days;
    exact.sort((a, b) => (a.shop === b.shop ? 0 : a.shop === "similar" ? -1 : 1) || nearer(a, b));
    differs.sort((a, b) => Math.abs(a.difference) - Math.abs(b.difference) || nearer(a, b));
    other.sort(nearer);
    const candidates = [...exact, ...differs, ...other].slice(0, MAX_CANDIDATES).map(({ shop: _shop, ...candidate }) => candidate);
    return { exact: null, candidates };
  }

  // src/engine/fixed-costs.ts
  var CADENCES = {
    monthly: {
      months: 1,
      min: 26,
      max: 35,
      grace: 45
    },
    quarterly: {
      months: 3,
      min: 85,
      max: 98,
      grace: 120
    },
    halfYearly: {
      months: 6,
      min: 175,
      max: 190,
      grace: 220
    },
    yearly: {
      months: 12,
      min: 355,
      max: 375,
      grace: 400
    }
  };
  var markID = (mark) => [mark.key, mark.side, mark.cadence, mark.anchor].join("");
  var date = (day2) => {
    const time = /^\d{4}-\d{2}-\d{2}$/.test(day2) ? Date.parse(day2 + "T12:00:00Z") : NaN;
    return Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === day2 ? time : NaN;
  };
  function nextFixedDay(day2, cadence) {
    const d = new Date(date(day2));
    const month = d.getUTCMonth() + CADENCES[cadence].months;
    const start = new Date(Date.UTC(d.getUTCFullYear(), month, 1, 12));
    const last2 = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0)).getUTCDate();
    start.setUTCDate(Math.min(d.getUTCDate(), last2));
    return start.toISOString().slice(0, 10);
  }
  var gap = (a, b) => (b - a) / 864e5;
  var distance = (a, b) => Math.min(Math.abs(a - b), 31 - Math.abs(a - b));
  var chronological = (a, b) => a.date - b.date || a.order - b.order;
  function usualDay(dates) {
    const days = dates.map((d) => new Date(d).getUTCDate());
    return Array.from(
      {
        length: 31
      },
      (_, i2) => {
        const distances = days.map((d) => distance(d, i2 + 1));
        return {
          day: i2 + 1,
          total: distances.reduce((a, b) => a + b, 0),
          close: distances.filter((d) => d <= 5).length
        };
      }
    ).sort((a, b) => a.total - b.total || b.close - a.close || a.day - b.day)[0];
  }
  var steady = (dates) => usualDay(dates).close * 4 >= dates.length * 3;
  function cadenceFor(dates, short = false) {
    if (dates.length < 2)
      return;
    const gaps = dates.slice(1).map((d, i2) => gap(dates[i2], d));
    return Object.keys(CADENCES).find(
      (key) => {
        const c = CADENCES[key];
        const within = (n) => n >= c.min && n <= c.max;
        const twice = (n) => n >= c.min * 2 && n <= c.max * 2;
        if (!short && dates.length < (c.months < 6 ? 3 : 2))
          return false;
        const normalized = gaps.map((n) => twice(n) ? n / 2 : n).sort((a, b) => a - b);
        const middle = Math.floor(normalized.length / 2);
        const median2 = normalized.length % 2 ? normalized[middle] : (normalized[middle - 1] + normalized[middle]) / 2;
        return gaps.some(within) && within(median2) && gaps.every((n) => n >= median2 / 2) && gaps.filter((n) => within(n) || twice(n)).length * 4 >= gaps.length * 3 && (c.months >= 6 || steady(dates));
      }
    );
  }
  function period(time, usual) {
    const d = new Date(time);
    const nearest = [-1, 0, 1].map(
      (offset) => {
        const start = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + offset, 1));
        const last2 = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 1, 0)).getUTCDate();
        start.setUTCDate(Math.min(usual, last2));
        return start;
      }
    ).sort((a, b) => Math.abs(a.getTime() - time) - Math.abs(b.getTime() - time))[0];
    return nearest.getUTCFullYear() * 12 + nearest.getUTCMonth();
  }
  function amountSeries(payments) {
    const result = [];
    for (const payment of payments) {
      const choices = result.map((s, i2) => ({
        i: i2,
        delta: Math.abs(s.at(-1).cents - payment.cents)
      })).filter((s) => s.delta <= Math.max(300, Math.round(payment.cents * 0.1))).sort((a, b) => a.delta - b.delta || a.i - b.i);
      if (choices.length)
        result[choices[0].i].push(payment);
      else
        result.push([payment]);
    }
    return result;
  }
  function mergePriceSteps(amounts) {
    const result = amounts.slice().sort((a, b) => chronological(a[0], b[0]));
    let changed = true;
    while (changed) {
      changed = false;
      for (let i2 = 0; i2 < result.length; i2++) {
        const previous = result[i2];
        const dates = previous.map((p) => p.date);
        const cadence = cadenceFor(dates, true);
        if (!cadence || !steady(dates))
          continue;
        const usual = usualDay(dates).day;
        const j = result.findIndex(
          (next, j2) => j2 !== i2 && previous.at(-1).date < next[0].date && cadenceFor(next.map((p) => p.date), true) === cadence && steady(next.map((p) => p.date)) && distance(usualDay(next.map((p) => p.date)).day, usual) <= 5 && period(next[0].date, usual) - period(previous.at(-1).date, usual) === CADENCES[cadence].months && cadenceFor([...dates, ...next.map((p) => p.date)]) === cadence
        );
        if (j < 0)
          continue;
        result[i2] = previous.concat(result[j]);
        result.splice(j, 1);
        changed = true;
        break;
      }
    }
    return result;
  }
  function splitCombined(payments) {
    let remaining2 = payments;
    const result = [];
    while (true) {
      const seeds = mergePriceSteps(amountSeries(remaining2)).sort((a, b) => a.at(-1).cents - b.at(-1).cents);
      const regular = seeds.flatMap(
        (seed) => {
          const cadence = cadenceFor(seed.map((p) => p.date));
          return cadence ? [{
            payments: seed,
            anchors: seed,
            cadence
          }] : [];
        }
      );
      let found;
      for (const seed of seeds) {
        if (seed.length < 2)
          continue;
        const dates = seed.map((p) => p.date);
        const original = cadenceFor(dates);
        if (!steady(dates) || original && CADENCES[original].months >= 6)
          continue;
        const gaps = dates.slice(1).map((d, i2) => gap(dates[i2], d));
        const ownIDs = new Set(seed.map((p) => p.row.id));
        const usual = usualDay(dates).day;
        const phase = period(dates[0], usual);
        for (const cadence of ["monthly", "quarterly"]) {
          const c = CADENCES[cadence];
          if (original && original !== cadence || !gaps.some((n) => n >= c.min && n <= c.max || n >= c.min * 2 && n <= c.max * 2))
            continue;
          const ownSlots = new Set(dates.map((d) => period(d, usual)));
          const carriedCents = (p) => seed.filter((s) => s.row.date <= p.row.date).at(-1)?.cents ?? seed[0].cents;
          const canCarry = (p) => (period(p.date, usual) - phase) % c.months === 0 && !ownSlots.has(
            period(p.date, usual)
          ) && distance(new Date(p.date).getUTCDate(), usual) <= 5 && p.cents > carriedCents(p);
          const reserved = new Set(regular.flatMap((s) => s.payments.map((p) => p.row.id)));
          const occupied = new Set(ownSlots);
          const augmented = seed.slice();
          for (const owner of regular) {
            if (CADENCES[owner.cadence].months < 6 || CADENCES[owner.cadence].months <= c.months || !owner.payments.every((p) => canCarry(p) && !occupied.has(period(p.date, usual))))
              continue;
            const extras = owner.payments.map((p) => ({
              ...p,
              cents: p.cents - carriedCents(p)
            }));
            if (mergePriceSteps(amountSeries(extras)).some(
              (s) => s.length === extras.length && cadenceFor(s.map((p) => p.date)) === owner.cadence
            )) {
              for (const p of owner.payments) {
                occupied.add(period(p.date, usual));
                augmented.push({
                  ...p,
                  cents: carriedCents(p)
                });
              }
            }
          }
          for (const p of remaining2) {
            const slot = period(p.date, usual);
            if (ownIDs.has(p.row.id) || reserved.has(p.row.id) || !canCarry(p) || occupied.has(slot))
              continue;
            occupied.add(slot);
            augmented.push({
              ...p,
              cents: carriedCents(p)
            });
          }
          augmented.sort(chronological);
          if (cadenceFor(augmented.map((p) => p.date)) !== cadence)
            continue;
          found = {
            payments: augmented,
            anchors: seed,
            cadence
          };
          break;
        }
        if (found)
          break;
      }
      if (!found)
        break;
      result.push(found);
      const allocated = new Map(found.payments.map((p) => [p.row.id, p.cents]));
      remaining2 = remaining2.map((p) => ({
        ...p,
        cents: p.cents - (allocated.get(p.row.id) ?? 0)
      })).filter((p) => p.cents > 0);
    }
    return result.concat(
      mergePriceSteps(amountSeries(remaining2)).map(
        (p) => ({
          payments: p,
          anchors: p,
          cadence: cadenceFor(p.map((p2) => p2.date))
        })
      )
    );
  }
  function fixedCostEntries(dashboard, marks = []) {
    const bank = dashboard.transactions.filter((t) => t.receiptId === void 0 && t.coveredBy === void 0);
    const reference = bank.map((p) => p.date).sort().at(-1);
    if (!reference)
      return [];
    const categories = new Map([...dashboard.categories, ...dashboard.incomeBuckets].map((c) => [c.name, c]));
    const groups2 = /* @__PURE__ */ new Map();
    bank.map((row, order) => ({
      row,
      order
    })).filter(
      ({ row }) => row.nameKey && !row.cashWithdrawal && (row.counted ?? row.amount) !== 0 && categories.get(row.categoryName)?.kind !== "transfer" && (row.categoriesIn.length || row.incomeBuckets.length) && Number.isFinite(date(row.date))
    ).sort((a, b) => a.row.date.localeCompare(b.row.date) || a.order - b.order).forEach(
      ({ row, order }) => {
        const key = row.nameKey + "" + (row.amount < 0 ? "expenses" : "income");
        const group = groups2.get(key) ?? [];
        group.push(
          {
            row,
            order,
            cents: Math.round(Math.abs(row.counted ?? row.amount) * 100),
            date: date(row.date)
          }
        );
        groups2.set(key, group);
      }
    );
    return [...groups2.keys()].sort().flatMap(
      (key) => {
        const series = splitCombined(groups2.get(key));
        return series.flatMap(
          (s) => {
            const { cadence, payments, anchors } = s;
            if (!cadence)
              return [];
            const newest = payments.at(-1).row;
            const first = payments[0].row.date;
            if (CADENCES[cadence].months >= 6 && series.some(
              (other) => !other.cadence && other.payments.some((p) => p.row.date >= first && p.row.date <= newest.date)
            ))
              return [];
            const side = newest.amount < 0 ? "expenses" : "income";
            const names2 = side === "expenses" ? newest.categoriesIn : newest.incomeBuckets;
            const category = categories.get(names2.includes(newest.categoryName) ? newest.categoryName : names2[0]);
            if (!category)
              return [];
            const stored = marks.filter(
              (m) => m.side === side && m.cadence === cadence && anchors.some((p) => p.row.id === m.anchor)
            );
            const anchor = anchors.slice().sort(
              (a, b) => (a.row.ledgerSequence ?? Number.MAX_SAFE_INTEGER) - (b.row.ledgerSequence ?? Number.MAX_SAFE_INTEGER)
            )[0].row;
            const mark = stored[0] ?? {
              key: anchor.fixedCostKey ?? anchor.nameKey,
              side,
              cadence,
              anchor: anchor.id
            };
            const cents7 = payments.at(-1).cents;
            const monthlyCents = Math.round(cents7 / CADENCES[cadence].months);
            return [
              {
                id: markID(mark),
                mark,
                newest,
                category,
                name: newest.place,
                side,
                cadence,
                cents: cents7,
                monthlyCents,
                amount: cents7 / 100,
                monthlyEquivalent: monthlyCents / 100,
                count: payments.length,
                first,
                last: newest.date,
                nextDue: nextFixedDay(newest.date, cadence),
                running: gap(date(newest.date), date(reference)) <= CADENCES[cadence].grace,
                notFixed: !!stored.length,
                exclusionIDs: stored.map(markID),
                ids: payments.slice().reverse().map((p) => p.row.id)
              }
            ];
          }
        );
      }
    );
  }
  function fixedCostList(entries, side) {
    const rows = entries.filter((e) => e.side === side);
    const ranked = (a, b) => b.monthlyCents - a.monthlyCents || a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
    const running = rows.filter((e) => e.running && !e.notFixed).sort(ranked);
    const monthlyCents = running.reduce((n, e) => n + e.monthlyCents, 0);
    return {
      running,
      ended: rows.filter((e) => !e.running && !e.notFixed).sort((a, b) => b.last.localeCompare(a.last) || a.id.localeCompare(b.id)),
      takenOut: rows.filter((e) => e.notFixed).sort(ranked),
      monthlyCents,
      monthlyTotal: monthlyCents / 100,
      yearlyTotal: monthlyCents * 12 / 100
    };
  }
  function monthlyAverage(dashboard, side) {
    const earliest = dashboard.transactions.map((t) => t.date).sort()[0];
    const late = Number(earliest?.slice(8)) > 7;
    const months = dashboard.months.filter((m) => !m.partial && !(late && m.key === earliest.slice(0, 7))).sort((a, b) => a.key.localeCompare(b.key));
    if (months.length < 2)
      return null;
    const cents7 = Math.round(
      months.reduce(
        (n, m) => n + Math.round((dashboard.byMonth[m.key]?.[side === "expenses" ? "expense" : "income"] ?? 0) * 100),
        0
      ) / months.length
    );
    return {
      cents: cents7,
      amount: cents7 / 100,
      count: months.length,
      first: months[0].key,
      last: months.at(-1).key
    };
  }

  // src/engine/quick-sort.ts
  function quickSortGroups(transactions, descriptions = {}) {
    const groups2 = /* @__PURE__ */ new Map();
    for (const p of transactions) {
      if (p.categoryName !== "Uncategorised" || !p.nameKey || p.coveredBy || !(p.categoriesIn.length || p.incomeBuckets.length))
        continue;
      const key = p.nameKey + "" + (p.amount > 0 ? "income" : "spend");
      const group = groups2.get(key) ?? [];
      group.push(p);
      groups2.set(key, group);
    }
    return [...groups2].map(
      ([key, rows]) => {
        rows = rows.slice().sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id));
        return {
          key,
          name: rows.at(-1).place,
          ids: rows.map((p) => p.id),
          count: rows.length,
          side: rows[0].amount > 0 ? "income" : "spend",
          total: rows.reduce((n, p) => n + Math.round(Math.abs(p.counted ?? p.amount) * 100), 0) / 100,
          first: rows[0].date,
          last: rows.at(-1).date,
          examples: [...new Set(rows.map((p) => descriptions[p.id] || p.bankName || p.place))].slice(0, 3)
        };
      }
    ).sort((a, b) => b.count - a.count || b.total - a.total || a.key.localeCompare(b.key));
  }

  // src/engine/ledger-dashboard.ts
  var emptyLedgerSettings = () => ({
    fixedCostMarks: [],
    names: {},
    links: {},
    paymentNames: {},
    ownNames: true,
    revision: 0,
    cashEntries: [],
    learned: {}
  });
  function buildLedgerDashboard(source, payments, settings = emptyLedgerSettings(), today = "") {
    const dashboard = buildDashboard(source);
    const keys = payments.map(merchantKey);
    const probes = payments.map((p) => merchantKey({
      counterparty: p.counterparty || p.description
    }));
    const universe = [...keys, ...probes, ...Object.keys(settings.names), ...Object.keys(settings.learned)];
    const resolved = shopIdentities(universe);
    const identities = resolved.slice(0, keys.length);
    const identityFor = new Map(universe.map((key, i2) => [key, resolved[i2]]));
    const rules = /* @__PURE__ */ new Map();
    for (const key of Object.keys(settings.names).sort()) {
      const identity = identityFor.get(key);
      if (!rules.has(identity))
        rules.set(identity, settings.names[key]);
    }
    const byId = new Map(payments.map((p, i2) => [p.id, {
      p,
      key: keys[i2],
      identity: identities[i2]
    }]));
    const bankNames = /* @__PURE__ */ new Map();
    for (const t of dashboard.transactions) {
      const info = byId.get(t.id);
      if (!info?.identity || t.receiptId || cardMerchant(t.place))
        continue;
      if (identityFor.get(merchantKey({
        counterparty: t.place
      })) === info.identity)
        bankNames.set(info.identity, t.place);
    }
    const transactions = dashboard.transactions.map(
      (t) => {
        const info = byId.get(t.id);
        if (!info)
          return {
            ...t,
            merchant: void 0,
            fixedCostKey: void 0,
            categorySource: void 0,
            isOwnName: false,
            nameKey: void 0,
            bankName: t.place,
            ownName: null,
            paymentOwnName: null,
            shopOwnName: null,
            ledgerSequence: void 0,
            paybackEligible: false
          };
        const paymentName = (Object.hasOwn(settings.paymentNames, t.id) ? settings.paymentNames[t.id] : void 0) ?? info.p.ownName;
        const shopName = Object.hasOwn(settings.names, info.key) ? settings.names[info.key] : rules.get(info.identity);
        const effective = paymentName === t.place ? void 0 : paymentName ?? shopName;
        const own = settings.ownNames ? effective : void 0;
        const place = t.receiptId ? t.place : own || bankNames.get(info.identity) || t.place;
        return {
          ...t,
          categorySource: info.p.categorySource,
          paybackEligible: (info.p.currency ?? "EUR") === "EUR" && !isCashWithdrawal(
            {
              ...info.p,
              description: info.p.description ?? "",
              externalId: t.id,
              category: t.categoryName,
              date: t.date,
              amount: t.amount,
              currency: info.p.currency ?? "EUR"
            }
          ) && !t.receiptId && !t.coveredBy && (t.categoriesIn.length > 0 || t.incomeBuckets.length > 0) && t.amount !== 0,
          place,
          bankName: t.place,
          merchant: info.identity,
          nameKey: own ? "own:" + own.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().normalize("NFC") : info.identity ? "merchant:" + info.identity : "bank:" + t.place,
          isOwnName: !!own,
          ownName: effective ?? null,
          paymentOwnName: paymentName ?? null,
          shopOwnName: shopName ?? null,
          fixedCostKey: info.key ? "merchant:" + info.key : "bank:" + t.place,
          ledgerSequence: info.p.sequence
        };
      }
    );
    const named = {
      ...dashboard,
      transactions
    };
    const entries = fixedCostEntries(named, settings.fixedCostMarks);
    const groups2 = /* @__PURE__ */ new Map();
    for (const p of transactions) {
      if (!p.nameKey || p.coveredBy || !(p.categoriesIn.length || p.incomeBuckets.length))
        continue;
      const rows = groups2.get(p.nameKey) ?? [];
      rows.push(p);
      groups2.set(p.nameKey, rows);
    }
    const nameGroups = Object.fromEntries(
      [...groups2].map(
        ([key, rows]) => {
          const ordered = rows.slice().sort(
            (a, b) => b.date.localeCompare(a.date) || (a.ledgerSequence ?? 0) - (b.ledgerSequence ?? 0)
          );
          const amounts = (payments2) => {
            const cents7 = (total, payment) => total + Math.round(Math.abs(payment.counted ?? payment.amount) * 100);
            return {
              moneyOut: payments2.filter((payment) => payment.amount < 0).reduce(cents7, 0) / 100,
              moneyIn: payments2.filter((payment) => payment.amount > 0).reduce(cents7, 0) / 100
            };
          };
          const months = dashboard.months.map((month) => {
            const payments2 = rows.filter((payment) => payment.month === month.key);
            return [month.key, { ...amounts(payments2), count: payments2.length }];
          });
          const aliases2 = ordered.flatMap((payment) => [
            payment.place,
            payment.bankName,
            payment.ownName,
            payment.paymentOwnName,
            payment.shopOwnName
          ].filter((name) => !!name));
          return [
            key,
            {
              key,
              name: ordered[0].place,
              rows: ordered.map((p) => p.id),
              count: rows.length,
              ...amounts(rows),
              months: Object.fromEntries(months),
              names: [...new Set(aliases2)],
              newestDate: ordered[0].date
            }
          ];
        }
      )
    );
    const summed = /* @__PURE__ */ new Map();
    for (const row of transactions) {
      if (!row.nameKey || row.coveredBy)
        continue;
      for (const [side, names2] of [["spend", row.categoriesIn], ["income", row.incomeBuckets]])
        for (const category of names2) {
          const listKey = JSON.stringify([category, row.month, side]);
          const groups3 = summed.get(listKey) ?? /* @__PURE__ */ new Map();
          const rows = groups3.get(row.nameKey) ?? [];
          rows.push(row);
          groups3.set(row.nameKey, rows);
          summed.set(listKey, groups3);
        }
    }
    const summedLists = Object.fromEntries(
      [...summed].map(
        ([listKey, groups3]) => {
          const [category, month, side] = JSON.parse(listKey);
          const rows = [...groups3].map(
            ([key, rows2]) => ({
              key,
              name: rows2.at(-1).place,
              ids: rows2.map((p) => p.id),
              count: rows2.length,
              amount: rows2.reduce((n, p) => n + Math.round((p.counted ?? p.amount) * 100), 0) / 100,
              latest: rows2.at(-1).date,
              covered: false
            })
          );
          for (const row of transactions)
            if (row.coveredBy && row.month === month && (side === "spend" ? row.categoriesIn : row.incomeBuckets).includes(category)) {
              rows.push(
                {
                  key: "covered:" + row.id,
                  name: row.place,
                  ids: [],
                  count: 1,
                  amount: row.counted ?? row.amount,
                  latest: row.date,
                  covered: true
                }
              );
            }
          return [listKey, rows.sort((a, b) => b.latest.localeCompare(a.latest) || a.key.localeCompare(b.key))];
        }
      )
    );
    const latest = dashboard.months.at(-1);
    const previous = dashboard.months.at(-2);
    const currentMonth = latest?.partial && Number(today.slice(8)) <= 7 && previous ? previous.key : latest?.key ?? null;
    return {
      ...named,
      today,
      currentMonth,
      nameGroups,
      summedLists,
      quickSort: quickSortGroups(transactions, Object.fromEntries(payments.map((p) => [p.id, p.description || ""]))),
      ownNames: settings.ownNames,
      monthlyAverage: {
        expenses: monthlyAverage(named, "expenses"),
        income: monthlyAverage(named, "income")
      },
      fixedCosts: {
        expenses: fixedCostList(entries, "expenses"),
        income: fixedCostList(entries, "income")
      }
    };
  }

  // src/engine/payback-plan.ts
  var centAmount = (n) => typeof n === "number" && Number.isFinite(n) && Number.isSafeInteger(Math.round(n * 100)) && Math.abs(n * 100 - Math.round(n * 100)) < 1e-7;
  var cents6 = (n) => Math.round(n * 100);
  var remaining = (p) => Math.min(
    cents6(Math.abs(p.amount)),
    cents6(Math.abs(p.counted ?? p.amount))
  );
  var compare5 = (a, b) => a.date.localeCompare(b.date) || (a.ledgerSequence ?? 0) - (b.ledgerSequence ?? 0) || a.id.localeCompare(b.id);
  function paybackChoices(dashboard, ids) {
    const wanted = new Set(ids);
    const selected = dashboard.transactions.filter((p) => wanted.has(p.id));
    if (!ids.length || wanted.size !== ids.length || selected.length !== ids.length || new Set(selected.map((p) => Math.sign(p.amount))).size !== 1)
      throw new Error("invalid-payment");
    const group = selected.filter((p) => p.paybackEligible && remaining(p) > 0).sort(compare5);
    if (!group.length)
      throw new Error("invalid-payment");
    const incoming = group[0].amount > 0;
    const total = group.reduce((n, p) => n + remaining(p), 0);
    const first = Date.parse(group[0].date);
    const last2 = Date.parse(group.at(-1).date);
    const candidates = dashboard.transactions.filter((p) => p.paybackEligible && remaining(p) > 0 && p.amount > 0 !== incoming).sort((a, b) => -compare5(a, b));
    const suggestions = candidates.flatMap(
      (candidate) => {
        const days = (Date.parse(candidate.date) - last2) / 864e5;
        const date2 = Date.parse(candidate.date);
        if (date2 < first - (incoming ? 120 : 30) * 864e5 || date2 > last2 + (incoming ? 30 : 120) * 864e5)
          return [];
        let fits;
        if (group.length === 1) {
          const expense = incoming ? candidate : group[0];
          const payer = incoming ? group[0] : candidate;
          const rest = remaining(expense);
          const original = cents6(Math.abs(expense.amount));
          fits = [
            ["whole", original],
            ["half", Math.round(original / 2)],
            ["third", Math.round(original / 3)],
            ["quarter", Math.round(original / 4)],
            ["rest", rest]
          ];
          const match2 = fits.find(([, n]) => n > 0 && n <= rest && Math.abs(remaining(payer) - n) <= 1);
          return [
            {
              id: candidate.id,
              fit: match2?.[0] ?? null,
              amount: Math.min(remaining(payer), rest, match2?.[1] ?? Infinity) / 100,
              distance: Math.abs(days)
            }
          ];
        }
        fits = incoming ? [["whole", total], ["half", total * 2]] : [
          ["whole", total],
          ["half", Math.round(total / 2)],
          ["third", Math.round(total / 3)],
          ["quarter", Math.round(total / 4)]
        ];
        const match = fits.find(([, n]) => n > 0 && Math.abs(remaining(candidate) - n) <= 1);
        return [
          {
            id: candidate.id,
            fit: match?.[0] ?? null,
            amount: Math.min(remaining(candidate), total) / 100,
            distance: Math.abs(days)
          }
        ];
      }
    ).sort(
      (a, b) => Number(!!b.fit) - Number(!!a.fit) || a.distance - b.distance || dashboard.transactions.find((p) => p.id === b.id).date.localeCompare(
        dashboard.transactions.find((p) => p.id === a.id).date
      ) || a.id.localeCompare(b.id)
    ).slice(0, 8);
    return {
      group,
      candidates,
      suggestions,
      rest: total / 100,
      skipped: selected.length - group.length
    };
  }
  function planPaybacks(dashboard, ids, others, typedAmount) {
    const choices = paybackChoices(dashboard, ids);
    const selected = new Set(others);
    if (selected.size !== others.length || !others.length)
      throw new Error("invalid-payment");
    const picked = choices.candidates.filter((p2) => selected.has(p2.id));
    if (picked.length !== others.length)
      throw new Error("invalid-payment");
    const expenses = (choices.group[0].amount < 0 ? choices.group : picked).slice().sort(compare5);
    const paymentsIn = (choices.group[0].amount > 0 ? choices.group : picked).slice().sort(compare5);
    if (typedAmount !== void 0 && (expenses.length !== 1 || paymentsIn.length !== 1 || !centAmount(typedAmount) || typedAmount <= 0 || cents6(typedAmount) > Math.min(remaining(expenses[0]), remaining(paymentsIn[0]))))
      throw new Error("invalid-amount");
    const open = expenses.map(remaining);
    const available = paymentsIn.map(remaining);
    const originalOpen = open.slice();
    const originalAvailable = available.slice();
    const links = [];
    let e = 0;
    let p = 0;
    while (e < expenses.length && p < paymentsIn.length) {
      if (!open[e]) {
        e++;
        continue;
      }
      if (!available[p]) {
        p++;
        continue;
      }
      const amount2 = typedAmount === void 0 ? Math.min(open[e], available[p]) : cents6(typedAmount);
      const from2 = paymentsIn[p];
      const to = expenses[e];
      const previous = from2.paysBack?.find((link) => link.payment === to.id)?.amount ?? 0;
      links.push(
        {
          from: from2.id,
          to: to.id,
          amount: amount2 / 100,
          totalAmount: (cents6(previous) + amount2) / 100
        }
      );
      open[e] -= amount2;
      available[p] -= amount2;
      if (typedAmount !== void 0)
        break;
    }
    return {
      links,
      expenses: expenses.map(
        (p2, i2) => ({
          id: p2.id,
          amount: (originalOpen[i2] - open[i2]) / 100,
          rest: open[i2] / 100
        })
      ),
      paymentsIn: paymentsIn.map(
        (p2, i2) => ({
          id: p2.id,
          amount: (originalAvailable[i2] - available[i2]) / 100,
          rest: available[i2] / 100
        })
      ),
      linked: links.reduce((n, l) => n + cents6(l.amount), 0) / 100,
      stillOpen: open.reduce((a, b) => a + b, 0) / 100,
      staysIncome: available.reduce((a, b) => a + b, 0) / 100
    };
  }
  function applyPlan(links, plan) {
    const result = JSON.parse(JSON.stringify(links));
    for (const link of plan.links) {
      if (!Object.hasOwn(result, link.from))
        Object.defineProperty(
          result,
          link.from,
          {
            value: [],
            enumerable: true,
            configurable: true,
            writable: true
          }
        );
      const rows = result[link.from];
      const i2 = rows.findIndex((l) => l.payment === link.to);
      if (i2 < 0)
        rows.push({
          payment: link.to,
          amount: link.totalAmount
        });
      else
        rows[i2].amount = link.totalAmount;
    }
    return result;
  }

  // src/engine/selection.ts
  function selectionSummary(transactions, ids, target) {
    const selected = new Set(ids);
    const rows = transactions.filter((p) => selected.has(p.id) && !p.coveredBy);
    if (rows.length !== selected.size || !rows.length || new Set(rows.map((p) => Math.sign(p.amount))).size !== 1)
      throw new Error("invalid-selection");
    const shops = new Set(rows.map((p) => p.merchant).filter(Boolean));
    const others = transactions.filter(
      (p) => !selected.has(p.id) && p.merchant && shops.has(p.merchant) && Math.sign(p.amount) === Math.sign(rows[0].amount) && !["manual", "structural", "receipt"].includes(p.categorySource || "") && (p.categoriesIn.length || p.incomeBuckets.length) && p.categoryName !== target
    );
    return {
      ids: rows.map((p) => p.id),
      count: rows.length,
      side: rows[0].amount > 0 ? "income" : "spend",
      total: rows.reduce((n, p) => n + Math.round(Math.abs(p.counted ?? p.amount) * 100), 0) / 100,
      shops: shops.size,
      otherCount: others.length,
      otherIDs: others.map((p) => p.id)
    };
  }

  // src/engine/index.ts
  var version = "0.1.0";
  function isoDates(file) {
    return {
      ...file,
      transactions: file.transactions.map(({ bookingDate: bookingDate2, valueDate, ...txn }) => ({
        ...txn,
        bookingDate: bookingDate2.toISOString(),
        ...valueDate === void 0 ? {} : { valueDate: valueDate?.toISOString() ?? null }
      }))
    };
  }
  var parseVrBankCsv2 = (text3) => isoDates(parseVrBankCsv(text3));
  var parseCamt2 = (text3) => isoDates(parseCamt(text3));
  var parsePaypalCsv3 = (text3) => isoDates(parsePaypalCsv2(text3));
  return __toCommonJS(index_exports);
})();
globalThis.AresiumEngine = __AresiumEngine;
