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
          for (let i = 0; i < len; i++) {
            if (arrayMode === "strict") {
              target[keys[i]] = [a[keys[i]]];
            } else {
              target[keys[i]] = a[keys[i]];
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
        for (let i = 0; i < xmlData.length; i++) {
          if (xmlData[i] === "<" && xmlData[i + 1] === "?") {
            i += 2;
            i = readPI(xmlData, i);
            if (i.err) return i;
          } else if (xmlData[i] === "<") {
            let tagStartPos = i;
            i++;
            if (xmlData[i] === "!") {
              i = readCommentAndCDATA(xmlData, i);
              continue;
            } else {
              let closingTag = false;
              if (xmlData[i] === "/") {
                closingTag = true;
                i++;
              }
              let tagName = "";
              for (; i < xmlData.length && xmlData[i] !== ">" && xmlData[i] !== " " && xmlData[i] !== "	" && xmlData[i] !== "\n" && xmlData[i] !== "\r"; i++) {
                tagName += xmlData[i];
              }
              tagName = tagName.trim();
              if (tagName[tagName.length - 1] === "/") {
                tagName = tagName.substring(0, tagName.length - 1);
                i--;
              }
              if (!validateTagName(tagName)) {
                let msg;
                if (tagName.trim().length === 0) {
                  msg = "Invalid space after '<'.";
                } else {
                  msg = "Tag '" + tagName + "' is an invalid name.";
                }
                return getErrorObject("InvalidTag", msg, getLineNumberForPosition(xmlData, i));
              }
              const result = readAttributeStr(xmlData, i);
              if (result === false) {
                return getErrorObject("InvalidAttr", "Attributes for '" + tagName + "' have open quote.", getLineNumberForPosition(xmlData, i));
              }
              let attrStr = result.value;
              i = result.index;
              if (attrStr[attrStr.length - 1] === "/") {
                const attrStrStart = i - attrStr.length;
                attrStr = attrStr.substring(0, attrStr.length - 1);
                const isValid = validateAttributeString(attrStr, options);
                if (isValid === true) {
                  tagFound = true;
                } else {
                  return getErrorObject(isValid.err.code, isValid.err.msg, getLineNumberForPosition(xmlData, attrStrStart + isValid.err.line));
                }
              } else if (closingTag) {
                if (!result.tagClosed) {
                  return getErrorObject("InvalidTag", "Closing tag '" + tagName + "' doesn't have proper closing.", getLineNumberForPosition(xmlData, i));
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
                  return getErrorObject(isValid.err.code, isValid.err.msg, getLineNumberForPosition(xmlData, i - attrStr.length + isValid.err.line));
                }
                if (reachedRoot === true) {
                  return getErrorObject("InvalidXml", "Multiple possible root nodes found.", getLineNumberForPosition(xmlData, i));
                } else if (options.unpairedTags.indexOf(tagName) !== -1) {
                } else {
                  tags.push({ tagName, tagStartPos });
                }
                tagFound = true;
              }
              for (i++; i < xmlData.length; i++) {
                if (xmlData[i] === "<") {
                  if (xmlData[i + 1] === "!") {
                    i++;
                    i = readCommentAndCDATA(xmlData, i);
                    continue;
                  } else if (xmlData[i + 1] === "?") {
                    i = readPI(xmlData, ++i);
                    if (i.err) return i;
                  } else {
                    break;
                  }
                } else if (xmlData[i] === "&") {
                  const afterAmp = validateAmpersand(xmlData, i);
                  if (afterAmp == -1)
                    return getErrorObject("InvalidChar", "char '&' is not expected.", getLineNumberForPosition(xmlData, i));
                  i = afterAmp;
                } else {
                  if (reachedRoot === true && !isWhiteSpace(xmlData[i])) {
                    return getErrorObject("InvalidXml", "Extra text at the end", getLineNumberForPosition(xmlData, i));
                  }
                }
              }
              if (xmlData[i] === "<") {
                i--;
              }
            }
          } else {
            if (isWhiteSpace(xmlData[i])) {
              continue;
            }
            return getErrorObject("InvalidChar", "char '" + xmlData[i] + "' is not expected.", getLineNumberForPosition(xmlData, i));
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
      function readPI(xmlData, i) {
        const start = i;
        for (; i < xmlData.length; i++) {
          if (xmlData[i] == "?" || xmlData[i] == " ") {
            const tagname = xmlData.substr(start, i - start);
            if (i > 5 && tagname === "xml") {
              return getErrorObject("InvalidXml", "XML declaration allowed only at the start of the document.", getLineNumberForPosition(xmlData, i));
            } else if (xmlData[i] == "?" && xmlData[i + 1] == ">") {
              i++;
              break;
            } else {
              continue;
            }
          }
        }
        return i;
      }
      function readCommentAndCDATA(xmlData, i) {
        if (xmlData.length > i + 5 && xmlData[i + 1] === "-" && xmlData[i + 2] === "-") {
          for (i += 3; i < xmlData.length; i++) {
            if (xmlData[i] === "-" && xmlData[i + 1] === "-" && xmlData[i + 2] === ">") {
              i += 2;
              break;
            }
          }
        } else if (xmlData.length > i + 8 && xmlData[i + 1] === "D" && xmlData[i + 2] === "O" && xmlData[i + 3] === "C" && xmlData[i + 4] === "T" && xmlData[i + 5] === "Y" && xmlData[i + 6] === "P" && xmlData[i + 7] === "E") {
          let angleBracketsCount = 1;
          for (i += 8; i < xmlData.length; i++) {
            if (xmlData[i] === "<") {
              angleBracketsCount++;
            } else if (xmlData[i] === ">") {
              angleBracketsCount--;
              if (angleBracketsCount === 0) {
                break;
              }
            }
          }
        } else if (xmlData.length > i + 9 && xmlData[i + 1] === "[" && xmlData[i + 2] === "C" && xmlData[i + 3] === "D" && xmlData[i + 4] === "A" && xmlData[i + 5] === "T" && xmlData[i + 6] === "A" && xmlData[i + 7] === "[") {
          for (i += 8; i < xmlData.length; i++) {
            if (xmlData[i] === "]" && xmlData[i + 1] === "]" && xmlData[i + 2] === ">") {
              i += 2;
              break;
            }
          }
        }
        return i;
      }
      var doubleQuote = '"';
      var singleQuote = "'";
      function readAttributeStr(xmlData, i) {
        let attrStr = "";
        let startChar = "";
        let tagClosed = false;
        for (; i < xmlData.length; i++) {
          if (xmlData[i] === doubleQuote || xmlData[i] === singleQuote) {
            if (startChar === "") {
              startChar = xmlData[i];
            } else if (startChar !== xmlData[i]) {
            } else {
              startChar = "";
            }
          } else if (xmlData[i] === ">") {
            if (startChar === "") {
              tagClosed = true;
              break;
            }
          }
          attrStr += xmlData[i];
        }
        if (startChar !== "") {
          return false;
        }
        return {
          value: attrStr,
          index: i,
          tagClosed
        };
      }
      var validAttrStrRegxp = new RegExp(`(\\s*)([^\\s=]+)(\\s*=)?(\\s*(['"])(([\\s\\S])*?)\\5)?`, "g");
      function validateAttributeString(attrStr, options) {
        const matches = util.getAllMatches(attrStr, validAttrStrRegxp);
        const attrNames = {};
        for (let i = 0; i < matches.length; i++) {
          if (matches[i][1].length === 0) {
            return getErrorObject("InvalidAttr", "Attribute '" + matches[i][2] + "' has no space in starting.", getPositionFromMatch(matches[i]));
          } else if (matches[i][3] !== void 0 && matches[i][4] === void 0) {
            return getErrorObject("InvalidAttr", "Attribute '" + matches[i][2] + "' is without value.", getPositionFromMatch(matches[i]));
          } else if (matches[i][3] === void 0 && !options.allowBooleanAttributes) {
            return getErrorObject("InvalidAttr", "boolean attribute '" + matches[i][2] + "' is not allowed.", getPositionFromMatch(matches[i]));
          }
          const attrName = matches[i][2];
          if (!validateAttrName(attrName)) {
            return getErrorObject("InvalidAttr", "Attribute '" + attrName + "' is an invalid name.", getPositionFromMatch(matches[i]));
          }
          if (!attrNames.hasOwnProperty(attrName)) {
            attrNames[attrName] = 1;
          } else {
            return getErrorObject("InvalidAttr", "Attribute '" + attrName + "' is repeated.", getPositionFromMatch(matches[i]));
          }
        }
        return true;
      }
      function validateNumberAmpersand(xmlData, i) {
        let re = /\d/;
        if (xmlData[i] === "x") {
          i++;
          re = /[\da-fA-F]/;
        }
        for (; i < xmlData.length; i++) {
          if (xmlData[i] === ";")
            return i;
          if (!xmlData[i].match(re))
            break;
        }
        return -1;
      }
      function validateAmpersand(xmlData, i) {
        i++;
        if (xmlData[i] === ";")
          return -1;
        if (xmlData[i] === "#") {
          i++;
          return validateNumberAmpersand(xmlData, i);
        }
        let count = 0;
        for (; i < xmlData.length; i++, count++) {
          if (xmlData[i].match(/\w/) && count < 20)
            continue;
          if (xmlData[i] === ";")
            break;
          return -1;
        }
        return i;
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
        addChild(node) {
          if (node.tagname === "__proto__") node.tagname = "#__proto__";
          if (node[":@"] && Object.keys(node[":@"]).length > 0) {
            this.child.push({ [node.tagname]: node.child, [":@"]: node[":@"] });
          } else {
            this.child.push({ [node.tagname]: node.child });
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
        readDocType(xmlData, i) {
          const entities = /* @__PURE__ */ Object.create(null);
          let entityCount = 0;
          if (xmlData[i + 3] === "O" && xmlData[i + 4] === "C" && xmlData[i + 5] === "T" && xmlData[i + 6] === "Y" && xmlData[i + 7] === "P" && xmlData[i + 8] === "E") {
            i = i + 9;
            let angleBracketsCount = 1;
            let hasBody = false, comment = false;
            let exp = "";
            for (; i < xmlData.length; i++) {
              if (xmlData[i] === "<" && !comment) {
                if (hasBody && hasSeq(xmlData, "!ENTITY", i)) {
                  i += 7;
                  let entityName, val;
                  [entityName, val, i] = this.readEntityExp(xmlData, i + 1, this.suppressValidationErr);
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
                } else if (hasBody && hasSeq(xmlData, "!ELEMENT", i)) {
                  i += 8;
                  const { index } = this.readElementExp(xmlData, i + 1);
                  i = index;
                } else if (hasBody && hasSeq(xmlData, "!ATTLIST", i)) {
                  i += 8;
                } else if (hasBody && hasSeq(xmlData, "!NOTATION", i)) {
                  i += 9;
                  const { index } = this.readNotationExp(xmlData, i + 1, this.suppressValidationErr);
                  i = index;
                } else if (hasSeq(xmlData, "!--", i)) {
                  comment = true;
                } else {
                  throw new Error(`Invalid DOCTYPE`);
                }
                angleBracketsCount++;
                exp = "";
              } else if (xmlData[i] === ">") {
                if (comment) {
                  if (xmlData[i - 1] === "-" && xmlData[i - 2] === "-") {
                    comment = false;
                    angleBracketsCount--;
                  }
                } else {
                  angleBracketsCount--;
                }
                if (angleBracketsCount === 0) {
                  break;
                }
              } else if (xmlData[i] === "[") {
                hasBody = true;
              } else {
                exp += xmlData[i];
              }
            }
            if (angleBracketsCount !== 0) {
              throw new Error(`Unclosed DOCTYPE`);
            }
          } else {
            throw new Error(`Invalid Tag instead of DOCTYPE`);
          }
          return { entities, i };
        }
        readEntityExp(xmlData, i) {
          i = skipWhitespace(xmlData, i);
          let entityName = "";
          while (i < xmlData.length && !/\s/.test(xmlData[i]) && xmlData[i] !== '"' && xmlData[i] !== "'") {
            entityName += xmlData[i];
            i++;
          }
          validateEntityName(entityName);
          i = skipWhitespace(xmlData, i);
          if (!this.suppressValidationErr) {
            if (xmlData.substring(i, i + 6).toUpperCase() === "SYSTEM") {
              throw new Error("External entities are not supported");
            } else if (xmlData[i] === "%") {
              throw new Error("Parameter entities are not supported");
            }
          }
          let entityValue = "";
          [i, entityValue] = this.readIdentifierVal(xmlData, i, "entity");
          if (this.options.enabled !== false && this.options.maxEntitySize != null && entityValue.length > this.options.maxEntitySize) {
            throw new Error(
              `Entity "${entityName}" size (${entityValue.length}) exceeds maximum allowed size (${this.options.maxEntitySize})`
            );
          }
          i--;
          return [entityName, entityValue, i];
        }
        readNotationExp(xmlData, i) {
          i = skipWhitespace(xmlData, i);
          let notationName = "";
          while (i < xmlData.length && !/\s/.test(xmlData[i])) {
            notationName += xmlData[i];
            i++;
          }
          !this.suppressValidationErr && validateEntityName(notationName);
          i = skipWhitespace(xmlData, i);
          const identifierType = xmlData.substring(i, i + 6).toUpperCase();
          if (!this.suppressValidationErr && identifierType !== "SYSTEM" && identifierType !== "PUBLIC") {
            throw new Error(`Expected SYSTEM or PUBLIC, found "${identifierType}"`);
          }
          i += identifierType.length;
          i = skipWhitespace(xmlData, i);
          let publicIdentifier = null;
          let systemIdentifier = null;
          if (identifierType === "PUBLIC") {
            [i, publicIdentifier] = this.readIdentifierVal(xmlData, i, "publicIdentifier");
            i = skipWhitespace(xmlData, i);
            if (xmlData[i] === '"' || xmlData[i] === "'") {
              [i, systemIdentifier] = this.readIdentifierVal(xmlData, i, "systemIdentifier");
            }
          } else if (identifierType === "SYSTEM") {
            [i, systemIdentifier] = this.readIdentifierVal(xmlData, i, "systemIdentifier");
            if (!this.suppressValidationErr && !systemIdentifier) {
              throw new Error("Missing mandatory system identifier for SYSTEM notation");
            }
          }
          return { notationName, publicIdentifier, systemIdentifier, index: --i };
        }
        readIdentifierVal(xmlData, i, type) {
          let identifierVal = "";
          const startChar = xmlData[i];
          if (startChar !== '"' && startChar !== "'") {
            throw new Error(`Expected quoted string, found "${startChar}"`);
          }
          i++;
          while (i < xmlData.length && xmlData[i] !== startChar) {
            identifierVal += xmlData[i];
            i++;
          }
          if (xmlData[i] !== startChar) {
            throw new Error(`Unterminated ${type} value`);
          }
          i++;
          return [i, identifierVal];
        }
        readElementExp(xmlData, i) {
          i = skipWhitespace(xmlData, i);
          let elementName = "";
          while (i < xmlData.length && !/\s/.test(xmlData[i])) {
            elementName += xmlData[i];
            i++;
          }
          if (!this.suppressValidationErr && !util.isName(elementName)) {
            throw new Error(`Invalid element name: "${elementName}"`);
          }
          i = skipWhitespace(xmlData, i);
          let contentModel = "";
          if (xmlData[i] === "E" && hasSeq(xmlData, "MPTY", i)) {
            i += 4;
          } else if (xmlData[i] === "A" && hasSeq(xmlData, "NY", i)) {
            i += 2;
          } else if (xmlData[i] === "(") {
            i++;
            while (i < xmlData.length && xmlData[i] !== ")") {
              contentModel += xmlData[i];
              i++;
            }
            if (xmlData[i] !== ")") {
              throw new Error("Unterminated content model");
            }
          } else if (!this.suppressValidationErr) {
            throw new Error(`Invalid Element Expression, found "${xmlData[i]}"`);
          }
          return {
            elementName,
            contentModel: contentModel.trim(),
            index: i
          };
        }
        readAttlistExp(xmlData, i) {
          i = skipWhitespace(xmlData, i);
          let elementName = "";
          while (i < xmlData.length && !/\s/.test(xmlData[i])) {
            elementName += xmlData[i];
            i++;
          }
          validateEntityName(elementName);
          i = skipWhitespace(xmlData, i);
          let attributeName = "";
          while (i < xmlData.length && !/\s/.test(xmlData[i])) {
            attributeName += xmlData[i];
            i++;
          }
          if (!validateEntityName(attributeName)) {
            throw new Error(`Invalid attribute name: "${attributeName}"`);
          }
          i = skipWhitespace(xmlData, i);
          let attributeType = "";
          if (xmlData.substring(i, i + 8).toUpperCase() === "NOTATION") {
            attributeType = "NOTATION";
            i += 8;
            i = skipWhitespace(xmlData, i);
            if (xmlData[i] !== "(") {
              throw new Error(`Expected '(', found "${xmlData[i]}"`);
            }
            i++;
            let allowedNotations = [];
            while (i < xmlData.length && xmlData[i] !== ")") {
              let notation = "";
              while (i < xmlData.length && xmlData[i] !== "|" && xmlData[i] !== ")") {
                notation += xmlData[i];
                i++;
              }
              notation = notation.trim();
              if (!validateEntityName(notation)) {
                throw new Error(`Invalid notation name: "${notation}"`);
              }
              allowedNotations.push(notation);
              if (xmlData[i] === "|") {
                i++;
                i = skipWhitespace(xmlData, i);
              }
            }
            if (xmlData[i] !== ")") {
              throw new Error("Unterminated list of notations");
            }
            i++;
            attributeType += " (" + allowedNotations.join("|") + ")";
          } else {
            while (i < xmlData.length && !/\s/.test(xmlData[i])) {
              attributeType += xmlData[i];
              i++;
            }
            const validTypes = ["CDATA", "ID", "IDREF", "IDREFS", "ENTITY", "ENTITIES", "NMTOKEN", "NMTOKENS"];
            if (!this.suppressValidationErr && !validTypes.includes(attributeType.toUpperCase())) {
              throw new Error(`Invalid attribute type: "${attributeType}"`);
            }
          }
          i = skipWhitespace(xmlData, i);
          let defaultValue = "";
          if (xmlData.substring(i, i + 8).toUpperCase() === "#REQUIRED") {
            defaultValue = "#REQUIRED";
            i += 8;
          } else if (xmlData.substring(i, i + 7).toUpperCase() === "#IMPLIED") {
            defaultValue = "#IMPLIED";
            i += 7;
          } else {
            [i, defaultValue] = this.readIdentifierVal(xmlData, i, "ATTLIST");
          }
          return {
            elementName,
            attributeName,
            attributeType,
            defaultValue,
            index: i
          };
        }
      };
      var skipWhitespace = (data, index) => {
        while (index < data.length && /\s/.test(data[index])) {
          index++;
        }
        return index;
      };
      function hasSeq(data, seq, i) {
        for (let j = 0; j < seq.length; j++) {
          if (seq[j] !== data[i + j + 1]) return false;
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
            for (let i = 0; i < this.options.stopNodes.length; i++) {
              const stopNodeExp = this.options.stopNodes[i];
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
        for (let i = 0; i < entKeys.length; i++) {
          const ent = entKeys[i];
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
          for (let i = 0; i < len; i++) {
            const attrName = this.resolveNameSpace(matches[i][1]);
            if (this.ignoreAttributesFn(attrName, jPath)) {
              continue;
            }
            let oldVal = matches[i][4];
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
        for (let i = 0; i < xmlData.length; i++) {
          const ch = xmlData[i];
          if (ch === "<") {
            if (xmlData[i + 1] === "/") {
              const closeIndex = findClosingIndex(xmlData, ">", i, "Closing Tag is not closed.");
              let tagName = xmlData.substring(i + 2, closeIndex).trim();
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
              i = closeIndex;
            } else if (xmlData[i + 1] === "?") {
              let tagData = readTagExp(xmlData, i, false, "?>");
              if (!tagData) throw new Error("Pi Tag is not closed.");
              textData = this.saveTextToParentTag(textData, currentNode, jPath);
              if (this.options.ignoreDeclaration && tagData.tagName === "?xml" || this.options.ignorePiTags) {
              } else {
                const childNode = new xmlNode(tagData.tagName);
                childNode.add(this.options.textNodeName, "");
                if (tagData.tagName !== tagData.tagExp && tagData.attrExpPresent) {
                  childNode[":@"] = this.buildAttributesMap(tagData.tagExp, jPath, tagData.tagName);
                }
                this.addChild(currentNode, childNode, jPath, i);
              }
              i = tagData.closeIndex + 1;
            } else if (xmlData.substr(i + 1, 3) === "!--") {
              const endIndex = findClosingIndex(xmlData, "-->", i + 4, "Comment is not closed.");
              if (this.options.commentPropName) {
                const comment = xmlData.substring(i + 4, endIndex - 2);
                textData = this.saveTextToParentTag(textData, currentNode, jPath);
                currentNode.add(this.options.commentPropName, [{ [this.options.textNodeName]: comment }]);
              }
              i = endIndex;
            } else if (xmlData.substr(i + 1, 2) === "!D") {
              const result = docTypeReader.readDocType(xmlData, i);
              this.docTypeEntities = result.entities;
              i = result.i;
            } else if (xmlData.substr(i + 1, 2) === "![") {
              const closeIndex = findClosingIndex(xmlData, "]]>", i, "CDATA is not closed.") - 2;
              const tagExp = xmlData.substring(i + 9, closeIndex);
              textData = this.saveTextToParentTag(textData, currentNode, jPath);
              let val = this.parseTextData(tagExp, currentNode.tagname, jPath, true, false, true, true);
              if (val == void 0) val = "";
              if (this.options.cdataPropName) {
                currentNode.add(this.options.cdataPropName, [{ [this.options.textNodeName]: tagExp }]);
              } else {
                currentNode.add(this.options.textNodeName, val);
              }
              i = closeIndex + 2;
            } else {
              let result = readTagExp(xmlData, i, this.options.removeNSPrefix);
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
              const startIndex = i;
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
                  i = result.closeIndex;
                } else if (this.options.unpairedTags.indexOf(tagName) !== -1) {
                  i = result.closeIndex;
                } else {
                  const result2 = this.readStopNodeData(xmlData, rawTagName, closeIndex + 1);
                  if (!result2) throw new Error(`Unexpected end of ${rawTagName}`);
                  i = result2.i;
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
                  i = result.closeIndex;
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
                i = closeIndex;
              }
            }
          } else {
            textData += xmlData[i];
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
      function tagExpWithClosingIndex(xmlData, i, closingChar = ">") {
        let attrBoundary;
        let tagExp = "";
        for (let index = i; index < xmlData.length; index++) {
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
      function findClosingIndex(xmlData, str, i, errMsg) {
        const closingIndex = xmlData.indexOf(str, i);
        if (closingIndex === -1) {
          throw new Error(errMsg);
        } else {
          return closingIndex + str.length - 1;
        }
      }
      function readTagExp(xmlData, i, removeNSPrefix, closingChar = ">") {
        const result = tagExpWithClosingIndex(xmlData, i + 1, closingChar);
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
      function readStopNodeData(xmlData, tagName, i) {
        const startIndex = i;
        let openTagCount = 1;
        for (; i < xmlData.length; i++) {
          if (xmlData[i] === "<") {
            if (xmlData[i + 1] === "/") {
              const closeIndex = findClosingIndex(xmlData, ">", i, `${tagName} is not closed`);
              let closeTagName = xmlData.substring(i + 2, closeIndex).trim();
              if (closeTagName === tagName) {
                openTagCount--;
                if (openTagCount === 0) {
                  return {
                    tagContent: xmlData.substring(startIndex, i),
                    i: closeIndex
                  };
                }
              }
              i = closeIndex;
            } else if (xmlData[i + 1] === "?") {
              const closeIndex = findClosingIndex(xmlData, "?>", i + 1, "StopNode is not closed.");
              i = closeIndex;
            } else if (xmlData.substr(i + 1, 3) === "!--") {
              const closeIndex = findClosingIndex(xmlData, "-->", i + 3, "StopNode is not closed.");
              i = closeIndex;
            } else if (xmlData.substr(i + 1, 2) === "![") {
              const closeIndex = findClosingIndex(xmlData, "]]>", i, "StopNode is not closed.") - 2;
              i = closeIndex;
            } else {
              const tagData = readTagExp(xmlData, i, ">");
              if (tagData) {
                const openTagName = tagData && tagData.tagName;
                if (openTagName === tagName && tagData.tagExp[tagData.tagExp.length - 1] !== "/") {
                  openTagCount++;
                }
                i = tagData.closeIndex;
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
      function prettify(node, options) {
        return compress(node, options);
      }
      function compress(arr2, options, jPath) {
        let text2;
        const compressedObj = {};
        for (let i = 0; i < arr2.length; i++) {
          const tagObj = arr2[i];
          const property = propName(tagObj);
          let newJpath = "";
          if (jPath === void 0) newJpath = property;
          else newJpath = jPath + "." + property;
          if (property === options.textNodeName) {
            if (text2 === void 0) text2 = tagObj[property];
            else text2 += "" + tagObj[property];
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
        if (typeof text2 === "string") {
          if (text2.length > 0) compressedObj[options.textNodeName] = text2;
        } else if (text2 !== void 0) compressedObj[options.textNodeName] = text2;
        return compressedObj;
      }
      function propName(obj) {
        const keys = Object.keys(obj);
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
          if (key !== ":@") return key;
        }
      }
      function assignAttributes(obj, attrMap, jpath, options) {
        if (attrMap) {
          const keys = Object.keys(attrMap);
          const len = keys.length;
          for (let i = 0; i < len; i++) {
            const atrrName = keys[i];
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
      var XMLParser2 = class {
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
      module.exports = XMLParser2;
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
      function arrToStr(arr2, options, jPath, indentation) {
        let xmlStr = "";
        let isPreviousElementTag = false;
        if (!Array.isArray(arr2)) {
          if (arr2 !== void 0 && arr2 !== null) {
            let text2 = arr2.toString();
            text2 = replaceEntitiesValue(text2, options);
            return text2;
          }
          return "";
        }
        for (let i = 0; i < arr2.length; i++) {
          const tagObj = arr2[i];
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
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
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
          for (let i = 0; i < options.entities.length; i++) {
            const entity = options.entities[i];
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
          for (let i = 0; i < this.options.entities.length; i++) {
            const entity = this.options.entities[i];
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
      var XMLParser2 = require_XMLParser();
      var XMLBuilder = require_json2xml();
      module.exports = {
        XMLParser: XMLParser2,
        XMLValidator: validator,
        XMLBuilder
      };
    }
  });

  // src/engine/index.ts
  var index_exports = {};
  __export(index_exports, {
    buildDashboard: () => buildDashboard,
    parseCamt: () => parseCamt2,
    parsePaypalCsv: () => parsePaypalCsv2,
    parseVrBankCsv: () => parseVrBankCsv2,
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
    for (var i = 0, len = code.length; i < len; ++i) {
      lookup[i] = code[i];
      revLookup[code.charCodeAt(i)] = i;
    }
    revLookup["-".charCodeAt(0)] = 62;
    revLookup["_".charCodeAt(0)] = 63;
  }
  function toByteArray(b64) {
    if (!inited) {
      init();
    }
    var i, j, l, tmp, placeHolders, arr2;
    var len = b64.length;
    if (len % 4 > 0) {
      throw new Error("Invalid string. Length must be a multiple of 4");
    }
    placeHolders = b64[len - 2] === "=" ? 2 : b64[len - 1] === "=" ? 1 : 0;
    arr2 = new Arr(len * 3 / 4 - placeHolders);
    l = placeHolders > 0 ? len - 4 : len;
    var L = 0;
    for (i = 0, j = 0; i < l; i += 4, j += 3) {
      tmp = revLookup[b64.charCodeAt(i)] << 18 | revLookup[b64.charCodeAt(i + 1)] << 12 | revLookup[b64.charCodeAt(i + 2)] << 6 | revLookup[b64.charCodeAt(i + 3)];
      arr2[L++] = tmp >> 16 & 255;
      arr2[L++] = tmp >> 8 & 255;
      arr2[L++] = tmp & 255;
    }
    if (placeHolders === 2) {
      tmp = revLookup[b64.charCodeAt(i)] << 2 | revLookup[b64.charCodeAt(i + 1)] >> 4;
      arr2[L++] = tmp & 255;
    } else if (placeHolders === 1) {
      tmp = revLookup[b64.charCodeAt(i)] << 10 | revLookup[b64.charCodeAt(i + 1)] << 4 | revLookup[b64.charCodeAt(i + 2)] >> 2;
      arr2[L++] = tmp >> 8 & 255;
      arr2[L++] = tmp & 255;
    }
    return arr2;
  }
  function tripletToBase64(num) {
    return lookup[num >> 18 & 63] + lookup[num >> 12 & 63] + lookup[num >> 6 & 63] + lookup[num & 63];
  }
  function encodeChunk(uint8, start, end) {
    var tmp;
    var output = [];
    for (var i = start; i < end; i += 3) {
      tmp = (uint8[i] << 16) + (uint8[i + 1] << 8) + uint8[i + 2];
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
    for (var i = 0, len2 = len - extraBytes; i < len2; i += maxChunkLength) {
      parts.push(encodeChunk(uint8, i, i + maxChunkLength > len2 ? len2 : i + maxChunkLength));
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
    var i = isLE ? nBytes - 1 : 0;
    var d = isLE ? -1 : 1;
    var s = buffer[offset + i];
    i += d;
    e = s & (1 << -nBits) - 1;
    s >>= -nBits;
    nBits += eLen;
    for (; nBits > 0; e = e * 256 + buffer[offset + i], i += d, nBits -= 8) {
    }
    m = e & (1 << -nBits) - 1;
    e >>= -nBits;
    nBits += mLen;
    for (; nBits > 0; m = m * 256 + buffer[offset + i], i += d, nBits -= 8) {
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
    var i = isLE ? 0 : nBytes - 1;
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
    for (; mLen >= 8; buffer[offset + i] = m & 255, i += d, m /= 256, mLen -= 8) {
    }
    e = e << mLen | m;
    eLen += mLen;
    for (; eLen > 0; buffer[offset + i] = e & 255, i += d, e /= 256, eLen -= 8) {
    }
    buffer[offset + i - d] |= s * 128;
  }
  var toString = {}.toString;
  var isArray = Array.isArray || function(arr2) {
    return toString.call(arr2) == "[object Array]";
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
  Buffer2._augment = function(arr2) {
    arr2.__proto__ = Buffer2.prototype;
    return arr2;
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
      for (var i = 0; i < size; ++i) {
        that[i] = 0;
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
    for (var i = 0; i < length; i += 1) {
      that[i] = array[i] & 255;
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
    var x = a.length;
    var y = b.length;
    for (var i = 0, len = Math.min(x, y); i < len; ++i) {
      if (a[i] !== b[i]) {
        x = a[i];
        y = b[i];
        break;
      }
    }
    if (x < y) return -1;
    if (y < x) return 1;
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
  Buffer2.concat = function concat(list, length) {
    if (!isArray(list)) {
      throw new TypeError('"list" argument must be an Array of Buffers');
    }
    if (list.length === 0) {
      return Buffer2.alloc(0);
    }
    var i;
    if (length === void 0) {
      length = 0;
      for (i = 0; i < list.length; ++i) {
        length += list[i].length;
      }
    }
    var buffer = Buffer2.allocUnsafe(length);
    var pos = 0;
    for (i = 0; i < list.length; ++i) {
      var buf = list[i];
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
    var i = b[n];
    b[n] = b[m];
    b[m] = i;
  }
  Buffer2.prototype.swap16 = function swap16() {
    var len = this.length;
    if (len % 2 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 16-bits");
    }
    for (var i = 0; i < len; i += 2) {
      swap(this, i, i + 1);
    }
    return this;
  };
  Buffer2.prototype.swap32 = function swap32() {
    var len = this.length;
    if (len % 4 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 32-bits");
    }
    for (var i = 0; i < len; i += 4) {
      swap(this, i, i + 3);
      swap(this, i + 1, i + 2);
    }
    return this;
  };
  Buffer2.prototype.swap64 = function swap64() {
    var len = this.length;
    if (len % 8 !== 0) {
      throw new RangeError("Buffer size must be a multiple of 64-bits");
    }
    for (var i = 0; i < len; i += 8) {
      swap(this, i, i + 7);
      swap(this, i + 1, i + 6);
      swap(this, i + 2, i + 5);
      swap(this, i + 3, i + 4);
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
    var max = INSPECT_MAX_BYTES;
    if (this.length > 0) {
      str = this.toString("hex", 0, max).match(/.{2}/g).join(" ");
      if (this.length > max) str += " ... ";
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
    var x = thisEnd - thisStart;
    var y = end - start;
    var len = Math.min(x, y);
    var thisCopy = this.slice(thisStart, thisEnd);
    var targetCopy = target.slice(start, end);
    for (var i = 0; i < len; ++i) {
      if (thisCopy[i] !== targetCopy[i]) {
        x = thisCopy[i];
        y = targetCopy[i];
        break;
      }
    }
    if (x < y) return -1;
    if (y < x) return 1;
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
  function arrayIndexOf(arr2, val, byteOffset, encoding, dir) {
    var indexSize = 1;
    var arrLength = arr2.length;
    var valLength = val.length;
    if (encoding !== void 0) {
      encoding = String(encoding).toLowerCase();
      if (encoding === "ucs2" || encoding === "ucs-2" || encoding === "utf16le" || encoding === "utf-16le") {
        if (arr2.length < 2 || val.length < 2) {
          return -1;
        }
        indexSize = 2;
        arrLength /= 2;
        valLength /= 2;
        byteOffset /= 2;
      }
    }
    function read2(buf, i2) {
      if (indexSize === 1) {
        return buf[i2];
      } else {
        return buf.readUInt16BE(i2 * indexSize);
      }
    }
    var i;
    if (dir) {
      var foundIndex = -1;
      for (i = byteOffset; i < arrLength; i++) {
        if (read2(arr2, i) === read2(val, foundIndex === -1 ? 0 : i - foundIndex)) {
          if (foundIndex === -1) foundIndex = i;
          if (i - foundIndex + 1 === valLength) return foundIndex * indexSize;
        } else {
          if (foundIndex !== -1) i -= i - foundIndex;
          foundIndex = -1;
        }
      }
    } else {
      if (byteOffset + valLength > arrLength) byteOffset = arrLength - valLength;
      for (i = byteOffset; i >= 0; i--) {
        var found = true;
        for (var j = 0; j < valLength; j++) {
          if (read2(arr2, i + j) !== read2(val, j)) {
            found = false;
            break;
          }
        }
        if (found) return i;
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
    var remaining = buf.length - offset;
    if (!length) {
      length = remaining;
    } else {
      length = Number(length);
      if (length > remaining) {
        length = remaining;
      }
    }
    var strLen = string.length;
    if (strLen % 2 !== 0) throw new TypeError("Invalid hex string");
    if (length > strLen / 2) {
      length = strLen / 2;
    }
    for (var i = 0; i < length; ++i) {
      var parsed = parseInt(string.substr(i * 2, 2), 16);
      if (isNaN(parsed)) return i;
      buf[offset + i] = parsed;
    }
    return i;
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
    var remaining = this.length - offset;
    if (length === void 0 || length > remaining) length = remaining;
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
    var i = start;
    while (i < end) {
      var firstByte = buf[i];
      var codePoint = null;
      var bytesPerSequence = firstByte > 239 ? 4 : firstByte > 223 ? 3 : firstByte > 191 ? 2 : 1;
      if (i + bytesPerSequence <= end) {
        var secondByte, thirdByte, fourthByte, tempCodePoint;
        switch (bytesPerSequence) {
          case 1:
            if (firstByte < 128) {
              codePoint = firstByte;
            }
            break;
          case 2:
            secondByte = buf[i + 1];
            if ((secondByte & 192) === 128) {
              tempCodePoint = (firstByte & 31) << 6 | secondByte & 63;
              if (tempCodePoint > 127) {
                codePoint = tempCodePoint;
              }
            }
            break;
          case 3:
            secondByte = buf[i + 1];
            thirdByte = buf[i + 2];
            if ((secondByte & 192) === 128 && (thirdByte & 192) === 128) {
              tempCodePoint = (firstByte & 15) << 12 | (secondByte & 63) << 6 | thirdByte & 63;
              if (tempCodePoint > 2047 && (tempCodePoint < 55296 || tempCodePoint > 57343)) {
                codePoint = tempCodePoint;
              }
            }
            break;
          case 4:
            secondByte = buf[i + 1];
            thirdByte = buf[i + 2];
            fourthByte = buf[i + 3];
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
      i += bytesPerSequence;
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
    var i = 0;
    while (i < len) {
      res += String.fromCharCode.apply(
        String,
        codePoints.slice(i, i += MAX_ARGUMENTS_LENGTH)
      );
    }
    return res;
  }
  function asciiSlice(buf, start, end) {
    var ret = "";
    end = Math.min(buf.length, end);
    for (var i = start; i < end; ++i) {
      ret += String.fromCharCode(buf[i] & 127);
    }
    return ret;
  }
  function latin1Slice(buf, start, end) {
    var ret = "";
    end = Math.min(buf.length, end);
    for (var i = start; i < end; ++i) {
      ret += String.fromCharCode(buf[i]);
    }
    return ret;
  }
  function hexSlice(buf, start, end) {
    var len = buf.length;
    if (!start || start < 0) start = 0;
    if (!end || end < 0 || end > len) end = len;
    var out = "";
    for (var i = start; i < end; ++i) {
      out += toHex(buf[i]);
    }
    return out;
  }
  function utf16leSlice(buf, start, end) {
    var bytes = buf.slice(start, end);
    var res = "";
    for (var i = 0; i < bytes.length; i += 2) {
      res += String.fromCharCode(bytes[i] + bytes[i + 1] * 256);
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
      for (var i = 0; i < sliceLen; ++i) {
        newBuf[i] = this[i + start];
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
    var i = 0;
    while (++i < byteLength2 && (mul *= 256)) {
      val += this[offset + i] * mul;
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
    var i = 0;
    while (++i < byteLength2 && (mul *= 256)) {
      val += this[offset + i] * mul;
    }
    mul *= 128;
    if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
    return val;
  };
  Buffer2.prototype.readIntBE = function readIntBE(offset, byteLength2, noAssert) {
    offset = offset | 0;
    byteLength2 = byteLength2 | 0;
    if (!noAssert) checkOffset(offset, byteLength2, this.length);
    var i = byteLength2;
    var mul = 1;
    var val = this[offset + --i];
    while (i > 0 && (mul *= 256)) {
      val += this[offset + --i] * mul;
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
  function checkInt(buf, value, offset, ext, max, min) {
    if (!internalIsBuffer(buf)) throw new TypeError('"buffer" argument must be a Buffer instance');
    if (value > max || value < min) throw new RangeError('"value" argument is out of bounds');
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
    var i = 0;
    this[offset] = value & 255;
    while (++i < byteLength2 && (mul *= 256)) {
      this[offset + i] = value / mul & 255;
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
    var i = byteLength2 - 1;
    var mul = 1;
    this[offset + i] = value & 255;
    while (--i >= 0 && (mul *= 256)) {
      this[offset + i] = value / mul & 255;
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
    for (var i = 0, j = Math.min(buf.length - offset, 2); i < j; ++i) {
      buf[offset + i] = (value & 255 << 8 * (littleEndian ? i : 1 - i)) >>> (littleEndian ? i : 1 - i) * 8;
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
    for (var i = 0, j = Math.min(buf.length - offset, 4); i < j; ++i) {
      buf[offset + i] = value >>> (littleEndian ? i : 3 - i) * 8 & 255;
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
      var limit = Math.pow(2, 8 * byteLength2 - 1);
      checkInt(this, value, offset, byteLength2, limit - 1, -limit);
    }
    var i = 0;
    var mul = 1;
    var sub = 0;
    this[offset] = value & 255;
    while (++i < byteLength2 && (mul *= 256)) {
      if (value < 0 && sub === 0 && this[offset + i - 1] !== 0) {
        sub = 1;
      }
      this[offset + i] = (value / mul >> 0) - sub & 255;
    }
    return offset + byteLength2;
  };
  Buffer2.prototype.writeIntBE = function writeIntBE(value, offset, byteLength2, noAssert) {
    value = +value;
    offset = offset | 0;
    if (!noAssert) {
      var limit = Math.pow(2, 8 * byteLength2 - 1);
      checkInt(this, value, offset, byteLength2, limit - 1, -limit);
    }
    var i = byteLength2 - 1;
    var mul = 1;
    var sub = 0;
    this[offset + i] = value & 255;
    while (--i >= 0 && (mul *= 256)) {
      if (value < 0 && sub === 0 && this[offset + i + 1] !== 0) {
        sub = 1;
      }
      this[offset + i] = (value / mul >> 0) - sub & 255;
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
  function checkIEEE754(buf, value, offset, ext, max, min) {
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
    var i;
    if (this === target && start < targetStart && targetStart < end) {
      for (i = len - 1; i >= 0; --i) {
        target[i + targetStart] = this[i + start];
      }
    } else if (len < 1e3 || !Buffer2.TYPED_ARRAY_SUPPORT) {
      for (i = 0; i < len; ++i) {
        target[i + targetStart] = this[i + start];
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
    var i;
    if (typeof val === "number") {
      for (i = start; i < end; ++i) {
        this[i] = val;
      }
    } else {
      var bytes = internalIsBuffer(val) ? val : utf8ToBytes(new Buffer2(val, encoding).toString());
      var len = bytes.length;
      for (i = 0; i < end - start; ++i) {
        this[i + start] = bytes[i % len];
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
    for (var i = 0; i < length; ++i) {
      codePoint = string.charCodeAt(i);
      if (codePoint > 55295 && codePoint < 57344) {
        if (!leadSurrogate) {
          if (codePoint > 56319) {
            if ((units -= 3) > -1) bytes.push(239, 191, 189);
            continue;
          } else if (i + 1 === length) {
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
    for (var i = 0; i < str.length; ++i) {
      byteArray.push(str.charCodeAt(i) & 255);
    }
    return byteArray;
  }
  function utf16leToBytes(str, units) {
    var c, hi, lo;
    var byteArray = [];
    for (var i = 0; i < str.length; ++i) {
      if ((units -= 2) < 0) break;
      c = str.charCodeAt(i);
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
    for (var i = 0; i < length; ++i) {
      if (i + offset >= dst.length || i >= src.length) break;
      dst[i + offset] = src[i];
    }
    return i;
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
    for (let i = 0, l = columns.length; i < l; i++) {
      const column = columns[i];
      if (column === void 0 || column === null || column === false) {
        normalizedColumns[i] = { disabled: true };
      } else if (typeof column === "string") {
        normalizedColumns[i] = { name: column };
      } else if (is_object(column)) {
        if (typeof column.name !== "string") {
          throw new CsvError("CSV_OPTION_COLUMNS_MISSING_NAME", [
            "Option columns missing name:",
            `property "name" is required at position ${i}`,
            "when column is an object literal"
          ]);
        }
        normalizedColumns[i] = column;
      } else {
        throw new CsvError("CSV_INVALID_COLUMN_DEFINITION", [
          "Invalid column definition:",
          "expect a string or a literal object,",
          `got ${JSON.stringify(column)} at position ${i}`
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
        const date = Date.parse(value);
        return !isNaN(date) ? new Date(date) : value;
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
    options.record_delimiter = options.record_delimiter.map(function(rd, i) {
      if (typeof rd !== "string" && !isBuffer(rd)) {
        throw new CsvError(
          "CSV_INVALID_OPTION_RECORD_DELIMITER",
          [
            "Invalid option `record_delimiter`:",
            "value must be a string, a buffer or array of string|buffer",
            `at index ${i},`,
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
            `at index ${i},`,
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
      (field) => field == null || field.toString && field.toString().trim() === ""
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
      __needMoreData: function(i, bufLen, end) {
        if (end) return false;
        const { encoding, escape, quote } = this.options;
        const { quoting, needMoreDataSize, recordDelimiterMaxLength } = this.state;
        const numOfCharLeft = bufLen - i - 1;
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
                  const err = this.__error(
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
                  if (err !== void 0) return err;
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
                    const err = this.__error(
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
                    if (err !== void 0) return err;
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
            const err = this.__error(
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
            if (err !== void 0) return err;
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
          const err = columns === false ? new CsvError(
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
            this.state.error = err;
          } else {
            const finalErr = this.__error(err);
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
            for (let i = 0, l = record.length; i < l; i++) {
              if (columns[i] === void 0 || columns[i].disabled) continue;
              if (group_columns_by_name === true && obj[columns[i].name] !== void 0) {
                if (Array.isArray(obj[columns[i].name])) {
                  obj[columns[i].name] = obj[columns[i].name].concat(record[i]);
                } else {
                  obj[columns[i].name] = [obj[columns[i].name], record[i]];
                }
              } else {
                obj[columns[i].name] = record[i];
              }
            }
            if (raw === true || info2 === true) {
              const extRecord = Object.assign(
                { record: obj },
                raw === true ? { raw: this.state.rawBuffer.toString(encoding) } : {},
                info2 === true ? { info: this.__infoRecord() } : {}
              );
              const err = this.__push(
                objname === void 0 ? extRecord : [obj[objname], extRecord],
                push
              );
              if (err) {
                return err;
              }
            } else {
              const err = this.__push(
                objname === void 0 ? obj : [obj[objname], obj],
                push
              );
              if (err) {
                return err;
              }
            }
          } else {
            if (raw === true || info2 === true) {
              const extRecord = Object.assign(
                { record },
                raw === true ? { raw: this.state.rawBuffer.toString(encoding) } : {},
                info2 === true ? { info: this.__infoRecord() } : {}
              );
              const err = this.__push(
                objname === void 0 ? extRecord : [record[objname], extRecord],
                push
              );
              if (err) {
                return err;
              }
            } else {
              const err = this.__push(
                objname === void 0 ? record : [record[objname], record],
                push
              );
              if (err) {
                return err;
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
        } catch (err) {
          return err;
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
        let field = this.state.field.toString(encoding);
        if (rtrim === true && wasQuoting === false) {
          field = field.trimRight();
        }
        if (cast === true) {
          const [err, f] = this.__cast(field);
          if (err !== void 0) return err;
          field = f;
        }
        this.state.record.push(field);
        if (max_record_size !== 0 && typeof field === "string") {
          this.state.record_length += field.length;
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
          } catch (err) {
            return err;
          }
          if (record === void 0 || record === null) {
            return;
          }
        }
        push(record);
      },
      // Return a tuple with the error and the casted value
      __cast: function(field) {
        const { columns, relax_column_count } = this.options;
        const isColumns = Array.isArray(columns);
        if (isColumns === true && relax_column_count && this.options.columns.length <= this.state.record.length) {
          return [void 0, void 0];
        }
        if (this.state.castField !== null) {
          try {
            const info2 = this.__infoField();
            return [void 0, this.state.castField.call(null, field, info2)];
          } catch (err) {
            return [err];
          }
        }
        if (this.__isFloat(field)) {
          return [void 0, parseFloat(field)];
        } else if (this.options.cast_date !== false) {
          const info2 = this.__infoField();
          return [void 0, this.options.cast_date.call(null, field, info2)];
        }
        return [void 0, field];
      },
      // Helper to test if a character is a space or a line delimiter
      __isCharTrimable: function(buf, pos) {
        const isTrim = (buf2, pos2) => {
          const { timchars } = this.state;
          loop1: for (let i = 0; i < timchars.length; i++) {
            const timchar = timchars[i];
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
        for (let i = 1; i < sourceLength; i++) {
          if (sourceBuf[i] !== targetBuf[targetPos + i]) return 0;
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
        loop1: for (let i = 0; i < delimiter.length; i++) {
          const del = delimiter[i];
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
        loop1: for (let i = 0; i < recordDelimiterLength; i++) {
          const rd = record_delimiter[i];
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
          for (let i = 0; i < l; i++) {
            if (escape[i] !== buf[pos + i]) {
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
        for (let i = 0; i < l; i++) {
          if (quote[i] !== buf[pos + i]) {
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
        loop: for (let i = 0; i < rds.length; i++) {
          const l = rds[i].length;
          for (let j = 0; j < l; j++) {
            if (rds[i][j] !== buf[pos + j]) {
              continue loop;
            }
          }
          this.options.record_delimiter.push(rds[i]);
          this.state.recordDelimiterMaxLength = rds[i].length;
          return rds[i].length;
        }
        return 0;
      },
      __error: function(msg) {
        const { encoding, raw, skip_records_with_error } = this.options;
        const err = typeof msg === "string" ? new Error(msg) : msg;
        if (skip_records_with_error) {
          this.state.recordHasError = true;
          if (this.options.on_skip !== void 0) {
            this.options.on_skip(
              err,
              raw ? this.state.rawBuffer.toString(encoding) : void 0
            );
          }
          return void 0;
        } else {
          return err;
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
    const parser2 = transform(opts);
    const push = (record) => {
      if (parser2.options.objname === void 0) records.push(record);
      else {
        records[record[0]] = record[1];
      }
    };
    const close = () => {
    };
    const err1 = parser2.parse(data, false, push, close);
    if (err1 !== void 0) throw err1;
    const err2 = parser2.parse(void 0, true, push, close);
    if (err2 !== void 0) throw err2;
    return records;
  };

  // src/import/sha1.ts
  function sha1(text2) {
    const bytes = [];
    for (const char of text2) {
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
    const rotate = (n, bits) => n << bits | n >>> 32 - bits;
    let h0 = 1732584193, h1 = 4023233417, h2 = 2562383102, h3 = 271733878, h4 = 3285377520;
    const words = new Int32Array(80);
    for (let offset = 0; offset < bytes.length; offset += 64) {
      for (let i = 0; i < 16; i++) {
        const p = offset + i * 4;
        words[i] = bytes[p] << 24 | bytes[p + 1] << 16 | bytes[p + 2] << 8 | bytes[p + 3];
      }
      for (let i = 16; i < 80; i++) words[i] = rotate(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1);
      let a = h0, b = h1, c = h2, d = h3, e = h4;
      for (let i = 0; i < 80; i++) {
        const f = i < 20 ? b & c | ~b & d : i < 40 ? b ^ c ^ d : i < 60 ? b & c | b & d | c & d : b ^ c ^ d;
        const k = i < 20 ? 1518500249 : i < 40 ? 1859775393 : i < 60 ? 2400959708 : 3395469782;
        const next = rotate(a, 5) + f + e + k + words[i] | 0;
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
      let amount = parseAmount(rawAmount);
      const sh = pick(row, COLS.sign);
      if (sh && /^(s|d|soll)/i.test(sh) && !amount.startsWith("-")) amount = `-${amount}`;
      iban = iban || pick(row, COLS.ownIban);
      const ccy = pick(row, COLS.currency) || "EUR";
      currency = ccy;
      const bookingDate = parseDateFlexible(pick(row, COLS.booking) ?? "");
      const valueRaw = pick(row, COLS.value);
      const purpose = pick(row, COLS.purpose) || pick(row, COLS.bookingText) || "(no description)";
      const counterparty = pick(row, COLS.name) || null;
      const balanceRaw = pick(row, COLS.balance);
      const externalId = sha1(`${bookingDate.toISOString()}|${amount}|${purpose}|${counterparty ?? ""}`).slice(0, 24);
      transactions.push({
        externalId,
        bookingDate,
        valueDate: valueRaw ? parseDateFlexible(valueRaw) : null,
        amount,
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
  function arr(x) {
    if (x === void 0 || x === null) return [];
    return Array.isArray(x) ? x : [x];
  }
  function textOf(node) {
    if (node && typeof node === "object" && "#text" in node) {
      return String(node["#text"]);
    }
    return node == null ? "" : String(node);
  }
  function parseCamt(xml) {
    const doc = parser.parse(xml);
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
        const amount = `${isDebit ? "-" : ""}${parseAmount(textOf(ntry.Amt))}`;
        const ccy = ntry.Amt && typeof ntry.Amt === "object" ? ntry.Amt["@_Ccy"] : void 0;
        const bookingDate = new Date(ntry.BookgDt?.Dt || ntry.BookgDt?.DtTm || ntry.ValDt?.Dt);
        const valueDate = ntry.ValDt?.Dt ? new Date(ntry.ValDt.Dt) : null;
        const tx = arr(ntry.NtryDtls?.TxDtls)[0];
        const remittance = arr(tx?.RmtInf?.Ustrd).map(textOf).join(" ").trim() || textOf(ntry.AddtlNtryInf).trim() || "(no description)";
        const creditor = tx?.RltdPties?.Cdtr?.Nm;
        const debtor = tx?.RltdPties?.Dbtr?.Nm;
        const counterpartyRaw = (isDebit ? creditor : debtor) || creditor || debtor;
        const counterparty = counterpartyRaw ? String(counterpartyRaw) : null;
        const ref = ntry.AcctSvcrRef || tx?.Refs?.AcctSvcrRef || tx?.Refs?.EndToEndId || tx?.Refs?.TxId;
        const externalId = ref && ref !== "NOTPROVIDED" ? String(ref) : sha1(`${bookingDate.toISOString()}|${amount}|${remittance}|${counterparty ?? ""}`).slice(0, 24);
        transactions.push({
          externalId,
          bookingDate,
          valueDate,
          amount,
          currency: ccy || currency,
          description: remittance,
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

  // src/data/dashboard.ts
  var money = (n) => Math.round(n * 100) / 100;
  var INCOME_META = {
    Refunds: { name: "Refunds", icon: "RotateCcw", color: "#34E27A", kind: "income" },
    Other: { name: "Other", icon: "CircleHelp", color: "#9AA6B8", kind: "income" }
  };
  function buildDashboard(source) {
    const { months, categories, balanceByDay } = source;
    const catByName = new Map(categories.map((c) => [c.name, c]));
    const incomeKeep = /* @__PURE__ */ new Set(["Tax", ...categories.filter((c) => c.kind !== "spend").map((c) => c.name)]);
    const monthIndex = new Map(months.map((m, i) => [m.key, i]));
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
      const dayBalance = Array.from({ length: mo.days }, (_, i) => balanceByDay[`${mo.key}-${String(i + 1).padStart(2, "0")}`] ?? 0);
      return [mo.key, {
        expense: 0,
        income: 0,
        categories: [],
        incomeBuckets: [],
        endBalance: balanceByDay[`${mo.key}-${String(mo.days).padStart(2, "0")}`],
        dayExpense: new Array(mo.days).fill(0),
        dayExpenseRunning: [],
        dayIncome: new Array(mo.days).fill(0),
        dayBalance
      }];
    }));
    const add = (map, name, amount) => map.set(name, (map.get(name) || 0) + amount);
    const transactions = [];
    for (const t of source.transactions) {
      const month = t.date.slice(0, 7);
      const day = parseInt(t.date.slice(8), 10);
      const index = monthIndex.get(month);
      const mo = index === void 0 ? void 0 : byMonth[month];
      const validDay = !!mo && day >= 1 && day <= mo.dayExpense.length;
      const tags = t.tags || [];
      const categoriesIn = [.../* @__PURE__ */ new Set([t.categoryName, ...tags])];
      const primaryBucket = !t.categoryName || t.categoryName === "Uncategorised" ? "Other" : incomeKeep.has(t.categoryName) ? t.categoryName : "Refunds";
      const buckets = t.amount > 0 ? [.../* @__PURE__ */ new Set([primaryBucket, ...tags.filter((n) => incomeKeep.has(n))])] : [];
      transactions.push({
        id: t.id,
        date: t.date,
        day,
        month,
        amount: t.amount,
        categoryName: t.categoryName,
        tags: [...tags],
        place: t.place,
        city: t.city,
        categoriesIn,
        incomeBuckets: buckets
      });
      if (catByName.get(t.categoryName)?.kind === "spend") {
        total.expense += -t.amount;
        if (mo) {
          mo.expense += -t.amount;
          if (validDay) mo.dayExpense[day - 1] += -t.amount;
        }
      }
      for (const name of categoriesIn) {
        const series = spend.get(name);
        if (!series) continue;
        add(categoryAll, name, -t.amount);
        if (index !== void 0) {
          add(categoryMonths[index], name, -t.amount);
          series.months[index] += -t.amount;
          if (validDay) series.days[month][day - 1] += -t.amount;
        }
      }
      if (t.amount > 0) {
        total.income += t.amount;
        if (mo) {
          mo.income += t.amount;
          if (validDay) mo.dayIncome[day - 1] += t.amount;
        }
        for (const bucket of buckets) {
          if (!income.has(bucket)) income.set(bucket, makeSeries());
          add(incomeAll, bucket, t.amount);
          if (index !== void 0) {
            add(incomeMonths[index], bucket, t.amount);
            const series = income.get(bucket);
            series.months[index] += t.amount;
            if (validDay) series.days[month][day - 1] += t.amount;
          }
        }
      }
    }
    const categoryRows = (totals) => categories.filter((c) => c.kind === "spend").map((c) => ({ name: c.name, total: money(totals.get(c.name) ?? 0) })).filter((c) => c.total > 0).sort((a, b) => b.total - a.total);
    const incomeRows = (totals) => [...totals].map(([name, n]) => ({ name, total: money(n) })).sort((a, b) => b.total - a.total);
    total.expense = money(total.expense);
    total.income = money(total.income);
    total.categories = categoryRows(categoryAll);
    total.incomeBuckets = incomeRows(incomeAll);
    months.forEach((m, i) => {
      const mo = byMonth[m.key];
      mo.expense = money(mo.expense);
      mo.income = money(mo.income);
      let running = 0;
      mo.dayExpenseRunning = mo.dayExpense.map((v) => money(running += v));
      mo.dayExpense = mo.dayExpense.map(money);
      mo.dayIncome = mo.dayIncome.map(money);
      mo.categories = categoryRows(categoryMonths[i]);
      mo.incomeBuckets = incomeRows(incomeMonths[i]);
    });
    for (const [map, round] of [[spend, (n) => money(Math.max(0, n))], [income, money]]) {
      for (const series of map.values()) {
        series.months = series.months.map(round);
        for (const m of months) series.days[m.key] = series.days[m.key].map(round);
      }
    }
    const ordered = (names, order) => names.slice().sort((a, b) => {
      const ia = order.indexOf(a), ib = order.indexOf(b);
      if (ia !== -1 && ib !== -1) return ia - ib;
      if (ia !== -1) return -1;
      if (ib !== -1) return 1;
      return a.localeCompare(b);
    });
    const databaseNames = new Set(source.databaseCategoryNames);
    const choices = categories.filter((c, i) => databaseNames.has(c.name) && categories.findIndex((other) => other.name === c.name) === i);
    const pick2 = {
      spend: ordered(choices.filter((c) => c.kind === "spend").map((c) => c.name), total.categories.map((r) => r.name)),
      income: ordered(choices.filter((c) => incomeKeep.has(c.name)).map((c) => c.name), total.incomeBuckets.map((r) => r.name))
    };
    return {
      version: 2,
      months,
      categories,
      pick: pick2,
      incomeBuckets: [...income.keys()].map((name) => catByName.get(name) ?? INCOME_META[name] ?? { name, icon: "Tag", color: "#34E27A", kind: "income" }),
      transactions,
      total,
      byMonth,
      spend: Object.fromEntries(spend),
      income: Object.fromEntries(income),
      overview: {
        expense: months.map((m) => byMonth[m.key].expense),
        income: months.map((m) => byMonth[m.key].income),
        balance: months.map((m) => byMonth[m.key].endBalance)
      }
    };
  }

  // src/engine/index.ts
  var version = "0.1.0";
  function isoDates(file) {
    return {
      ...file,
      transactions: file.transactions.map(({ bookingDate, valueDate, ...txn }) => ({
        ...txn,
        bookingDate: bookingDate.toISOString(),
        ...valueDate === void 0 ? {} : { valueDate: valueDate?.toISOString() ?? null }
      }))
    };
  }
  var parseVrBankCsv2 = (text2) => isoDates(parseVrBankCsv(text2));
  var parseCamt2 = (text2) => isoDates(parseCamt(text2));
  var parsePaypalCsv2 = (text2) => isoDates(parsePaypalCsv(text2));
  return __toCommonJS(index_exports);
})();
globalThis.AresiumEngine = __AresiumEngine;
