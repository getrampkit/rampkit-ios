import Foundation

/// Pre-defined JavaScript scripts for injection into WebViews
enum InjectedScripts {
    
    /// Dynamic tap behavior evaluation script
    /// Handles conditional tap actions based on state variables
    /// Must be injected AFTER window.__rampkitVars is available
    static let dynamicTapHandler = """
    (function() {
        'use strict';
        
        // Skip if already applied
        if (window.__rampkitDynamicTapApplied) return;
        window.__rampkitDynamicTapApplied = true;
        
        /**
         * Get the current state variables for condition evaluation
         * Uses window.__rampkitVars if available, falls back to window.__rampkitVariables
         */
        function getVars() {
            return window.__rampkitVars || window.__rampkitVariables || {};
        }
        
        /**
         * Evaluate a single rule against current variables
         * @param {Object} rule - { key: string, op: string, value: any }
         * @param {Object} vars - Current state variables
         * @returns {boolean}
         */
        function evaluateRule(rule, vars) {
            if (!rule || !rule.key) return false;
            
            var leftValue = vars[rule.key];
            var rightValue = rule.value;
            var op = rule.op || '=';
            
            // Handle null/undefined
            if (leftValue === undefined || leftValue === null) leftValue = '';
            if (rightValue === undefined || rightValue === null) rightValue = '';
            
            // Normalize string comparisons
            var leftStr = String(leftValue);
            var rightStr = String(rightValue);
            
            switch (op) {
                case '=':
                case '==':
                    // Loose equality - handles string/number/boolean comparisons
                    if (typeof leftValue === 'boolean' || typeof rightValue === 'boolean') {
                        // Convert "true"/"false" strings to booleans
                        var leftBool = leftValue === true || leftValue === 'true';
                        var rightBool = rightValue === true || rightValue === 'true';
                        return leftBool === rightBool;
                    }
                    return leftStr === rightStr;
                    
                case '!=':
                case '<>':
                    if (typeof leftValue === 'boolean' || typeof rightValue === 'boolean') {
                        var leftBool = leftValue === true || leftValue === 'true';
                        var rightBool = rightValue === true || rightValue === 'true';
                        return leftBool !== rightBool;
                    }
                    return leftStr !== rightStr;
                    
                case '>':
                    return parseFloat(leftValue) > parseFloat(rightValue);
                    
                case '<':
                    return parseFloat(leftValue) < parseFloat(rightValue);
                    
                case '>=':
                    return parseFloat(leftValue) >= parseFloat(rightValue);
                    
                case '<=':
                    return parseFloat(leftValue) <= parseFloat(rightValue);
                    
                case 'contains':
                    return leftStr.indexOf(rightStr) !== -1;
                    
                case 'startsWith':
                    return leftStr.indexOf(rightStr) === 0;
                    
                case 'endsWith':
                    return leftStr.slice(-rightStr.length) === rightStr;
                    
                case 'empty':
                case 'isEmpty':
                    return leftStr === '' || leftValue === null || leftValue === undefined;
                    
                case 'notEmpty':
                case 'isNotEmpty':
                    return leftStr !== '' && leftValue !== null && leftValue !== undefined;
                    
                default:
                    console.log('[RampKit] Unknown operator:', op);
                    return false;
            }
        }
        
        /**
         * Evaluate all rules in a condition (AND logic)
         * @param {Array} rules - Array of rule objects
         * @param {Object} vars - Current state variables
         * @returns {boolean}
         */
        function evaluateRules(rules, vars) {
            if (!rules || !Array.isArray(rules) || rules.length === 0) {
                return true; // No rules = always true (for 'else' conditions)
            }
            
            // All rules must pass (AND logic)
            for (var i = 0; i < rules.length; i++) {
                if (!evaluateRule(rules[i], vars)) {
                    return false;
                }
            }
            return true;
        }
        
        /**
         * Execute a single tap action
         * @param {Object} action - The action object with type and params
         */
        function executeTapAction(action) {
            if (!action || !action.type) {
                console.log('[RampKit] executeTapAction: No action type');
                return;
            }
            
            console.log('[RampKit] executeTapAction:', action.type, action);
            
            var message = null;
            
            switch (action.type) {
                case 'navigate':
                    message = {
                        type: 'rampkit:navigate',
                        targetScreenId: action.targetScreenId || '__continue__',
                        animation: action.animation || 'fade'
                    };
                    break;
                    
                case 'continue':
                    message = {
                        type: 'rampkit:navigate',
                        targetScreenId: '__continue__',
                        animation: action.animation || 'fade'
                    };
                    break;
                    
                case 'goBack':
                    message = {
                        type: 'rampkit:goBack',
                        animation: action.animation || 'fade'
                    };
                    break;
                    
                case 'close':
                    message = { type: 'rampkit:close' };
                    break;
                    
                case 'haptic':
                    message = {
                        type: 'rampkit:haptic',
                        hapticType: action.hapticType || 'impact',
                        impactStyle: action.impactStyle || 'Medium',
                        notificationType: action.notificationType || null
                    };
                    break;
                    
                case 'showPaywall':
                    message = {
                        type: 'rampkit:show-paywall',
                        payload: action.payload || { paywallId: action.paywallId }
                    };
                    break;
                    
                case 'requestReview':
                    // Prevent duplicate review requests in the same session
                    if (!window.__rampkitReviewRequested) {
                        window.__rampkitReviewRequested = true;
                        message = { type: 'rampkit:request-review' };
                    } else {
                        console.log('[RampKit] Skipping duplicate review request (tap)');
                        return;
                    }
                    break;
                    
                case 'requestNotificationPermission':
                    message = {
                        type: 'rampkit:request-notification-permission',
                        ios: action.ios,
                        android: action.android
                    };
                    break;
                    
                case 'onboardingFinished':
                case 'finishOnboarding':
                case 'finish':
                    message = {
                        type: 'rampkit:onboarding-finished',
                        payload: action.payload
                    };
                    break;
                    
                case 'setVariable':
                    // Update local state and notify native
                    if (action.key) {
                        var vars = getVars();
                        vars[action.key] = action.value;
                        
                        // Update global state
                        if (window.__rampkitVariables) {
                            window.__rampkitVariables[action.key] = action.value;
                        }
                        if (window.__rampkitVars) {
                            window.__rampkitVars[action.key] = action.value;
                        }
                        
                        // Notify native side
                        var updateVars = {};
                        updateVars[action.key] = action.value;
                        if (typeof window.rampkitUpdateVariables === 'function') window.rampkitUpdateVariables(updateVars);
                        message = {
                            type: 'rampkit:variables',
                            vars: updateVars
                        };
                    }
                    break;
                    
                case 'openURL':
                    if (action.url) {
                        try {
                            window.open(action.url, '_blank');
                        } catch (e) {
                            console.log('[RampKit] Failed to open URL:', e);
                        }
                    }
                    return; // Don't send message for URL open

                case 'addClass':
                    // Add class to elements matching selector (or tapped element)
                    if (action.class) {
                        var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                        targets.forEach(function(el) { if (el) el.classList.add(action.class); });
                    }
                    return;

                case 'removeClass':
                    // Remove class from elements matching selector (or tapped element)
                    if (action.class) {
                        var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                        targets.forEach(function(el) { if (el) el.classList.remove(action.class); });
                    }
                    return;

                case 'toggleClass':
                    // Toggle class on elements matching selector (or tapped element)
                    if (action.class) {
                        var targets = action.selector ? document.querySelectorAll(action.selector) : [window.__rampkitCurrentTapElement];
                        targets.forEach(function(el) { if (el) el.classList.toggle(action.class); });
                    }
                    return;

                case 'selectOne':
                    // Radio-button behavior: remove class from all matching selector, add to tapped element
                    if (action.class && action.selector) {
                        document.querySelectorAll(action.selector).forEach(function(el) {
                            el.classList.remove(action.class);
                        });
                        if (window.__rampkitCurrentTapElement) {
                            window.__rampkitCurrentTapElement.classList.add(action.class);
                        }
                    }
                    return;

                case 'none':
                    // Do nothing
                    return;

                default:
                    console.log('[RampKit] Unknown action type:', action.type);
                    return;
            }
            
            // Send message to native if we have one
            if (message) {
                try {
                    if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
                        window.ReactNativeWebView.postMessage(JSON.stringify(message));
                    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rampkit) {
                        window.webkit.messageHandlers.rampkit.postMessage(JSON.stringify(message));
                    }
                } catch (e) {
                    console.log('[RampKit] Failed to send message:', e);
                }
            }
        }
        
        /**
         * Evaluate dynamic tap conditions and execute matched actions
         * @param {Object} tapDynamic - The tapDynamic configuration object
         * @returns {boolean} - True if a condition was matched and actions executed
         */
        function evaluateDynamicTap(tapDynamic) {
            if (!tapDynamic || !tapDynamic.values || !Array.isArray(tapDynamic.values)) {
                console.log('[RampKit] evaluateDynamicTap: Invalid tapDynamic');
                return false;
            }
            
            var vars = getVars();
            console.log('[RampKit] evaluateDynamicTap with vars:', JSON.stringify(vars));
            
            var conditions = tapDynamic.values;
            
            for (var i = 0; i < conditions.length; i++) {
                var condition = conditions[i];
                var conditionType = condition.conditionType || 'if';
                var rules = condition.rules || [];
                var actions = condition.actions || [];
                
                console.log('[RampKit] Checking condition', i, ':', conditionType, 'rules:', rules.length);
                
                // 'else' always matches if we reach it
                if (conditionType === 'else') {
                    console.log('[RampKit] Matched else condition');
                    for (var j = 0; j < actions.length; j++) {
                        executeTapAction(actions[j]);
                    }
                    return true;
                }
                
                // 'if' and 'elseif' evaluate rules
                if (evaluateRules(rules, vars)) {
                    console.log('[RampKit] Matched', conditionType, 'condition');
                    for (var j = 0; j < actions.length; j++) {
                        executeTapAction(actions[j]);
                    }
                    return true;
                }
            }
            
            console.log('[RampKit] No conditions matched');
            return false;
        }
        
        /**
         * Decode HTML entities in a string (for HTML-encoded JSON)
         */
        function decodeHtmlEntities(str) {
            if (!str) return str;
            return str
                .replace(/&quot;/g, '"')
                .replace(/&#34;/g, '"')
                .replace(/&#x22;/g, '"')
                .replace(/&apos;/g, "'")
                .replace(/&#39;/g, "'")
                .replace(/&#x27;/g, "'")
                .replace(/&lt;/g, '<')
                .replace(/&gt;/g, '>')
                .replace(/&amp;/g, '&');
        }
        
        /**
         * Handle tap event on an element with dynamic tap behavior
         * Called from tap/click handlers
         * @param {HTMLElement} element - The tapped element
         * @returns {boolean} - True if handled, false to fall back to static actions
         */
        function handleDynamicTap(element) {
            if (!element) {
                console.log('[RampKit] handleDynamicTap: No element provided');
                return false;
            }

            // Store the tapped element for use by class manipulation actions
            window.__rampkitCurrentTapElement = element;

            console.log('[RampKit] handleDynamicTap called on:', element.tagName, element.className);
            
            // Check for data-tap-dynamic attribute
            var tapDynamicAttr = element.getAttribute('data-tap-dynamic');
            
            // Also check for dataset version (in case attribute name is camelCased)
            if (!tapDynamicAttr && element.dataset && element.dataset.tapDynamic) {
                tapDynamicAttr = element.dataset.tapDynamic;
            }
            
            if (!tapDynamicAttr) {
                // Walk up the DOM to find parent with dynamic tap
                var parent = element.parentElement;
                var depth = 0;
                while (parent && depth < 10) {
                    tapDynamicAttr = parent.getAttribute('data-tap-dynamic');
                    if (!tapDynamicAttr && parent.dataset && parent.dataset.tapDynamic) {
                        tapDynamicAttr = parent.dataset.tapDynamic;
                    }
                    if (tapDynamicAttr) {
                        console.log('[RampKit] Found data-tap-dynamic on parent at depth', depth);
                        break;
                    }
                    parent = parent.parentElement;
                    depth++;
                }
            }
            
            if (!tapDynamicAttr) {
                console.log('[RampKit] handleDynamicTap: No data-tap-dynamic attribute found');
                return false;
            }
            
            console.log('[RampKit] Raw data-tap-dynamic:', tapDynamicAttr.substring(0, 200));
            
            try {
                // Decode HTML entities first (in case JSON is HTML-encoded)
                var decodedAttr = decodeHtmlEntities(tapDynamicAttr);
                console.log('[RampKit] Decoded data-tap-dynamic:', decodedAttr.substring(0, 200));
                
                var tapDynamic = JSON.parse(decodedAttr);
                console.log('[RampKit] Parsed tapDynamic:', JSON.stringify(tapDynamic).substring(0, 200));
                
                return evaluateDynamicTap(tapDynamic);
            } catch (e) {
                console.log('[RampKit] Failed to parse data-tap-dynamic:', e.message);
                console.log('[RampKit] Attribute value was:', tapDynamicAttr);
                return false;
            }
        }
        
        // Expose functions globally for use by tap handlers
        window.__rampkitExecuteTapAction = executeTapAction;
        window.__rampkitEvaluateDynamicTap = evaluateDynamicTap;
        window.__rampkitHandleDynamicTap = handleDynamicTap;
        
        console.log('[RampKit] Dynamic tap handler installed');
    })();
    """
    
    /// Template resolution script for device/user variables
    /// Resolves ${device.platform}, ${user.id}, ${variableName} etc.
    /// Also supports ternary expressions: ${username == "james" ? "Hello James" : "Hello"}
    /// Supported operators: ==, !=, >, <, >=, <= and truthy checks
    /// Must be called AFTER window.rampkitContext is injected
    static let templateResolver = """
    (function() {
        'use strict';
        
        // Skip if already applied
        if (window.__rampkitTemplatesResolved) return;
        
        var ctx = window.rampkitContext || { device: {}, user: {} };
        var stateVars = window.__rampkitVariables || {};
        
        // Build flat variable map for template lookup (make it accessible for updates)
        window.__rampkitVars = {};
        var vars = window.__rampkitVars;
        
        // Storage for original templates (to enable re-resolution on variable updates)
        var templateStore = [];
        var attrTemplateStore = [];
        
        // Rebuild vars from context and state
        function rebuildVars() {
            // Clear existing
            for (var key in vars) {
                if (vars.hasOwnProperty(key)) delete vars[key];
            }
            
            // Device variables (e.g., device.platform -> "iOS")
            if (ctx.device) {
                Object.keys(ctx.device).forEach(function(key) {
                    vars['device.' + key] = ctx.device[key];
                });
            }
            
            // User variables (e.g., user.id -> "abc123")
            if (ctx.user) {
                Object.keys(ctx.user).forEach(function(key) {
                    vars['user.' + key] = ctx.user[key];
                });
            }
            
            // State variables (flat, e.g., myVar -> "value")
            Object.keys(stateVars).forEach(function(key) {
                vars[key] = stateVars[key];
            });
        }
        
        // Initial build
        rebuildVars();
        
        // Newline handling constants (using char codes to avoid Swift escape issues)
        var BACKSLASH = String.fromCharCode(92); // backslash character
        var BACKSLASH_N = BACKSLASH + 'n';       // literal \\n (2 chars)
        var DOUBLE_BACKSLASH_N = BACKSLASH + BACKSLASH + 'n'; // literal \\\\n (3 chars)
        
        // Helper: resolve a value (strip quotes or get variable value)
        function resolveValue(value) {
            if (!value) return '';
            value = value.trim();
            
            // Check for double-quoted string: "..."
            var doubleQuoteMatch = value.match(/^"(.*)"$/);
            if (doubleQuoteMatch) {
                return doubleQuoteMatch[1];
            }
            
            // Check for single-quoted string: '...'
            var singleQuoteMatch = value.match(/^'(.*)'$/);
            if (singleQuoteMatch) {
                return singleQuoteMatch[1];
            }
            
            // Check if it's a variable reference
            if (/^[A-Za-z_][A-Za-z0-9_.]*$/.test(value)) {
                var varValue = vars[value];
                if (varValue !== undefined && varValue !== null) {
                    return String(varValue);
                }
                return '';
            }
            
            // Check for numeric value
            if (/^-?\\d+(\\.\\d+)?$/.test(value)) {
                return value;
            }
            
            return value;
        }
        
        // Helper: evaluate a condition expression
        function evaluateCondition(condition) {
            if (!condition) return false;
            condition = condition.trim();
            
            // Equality: var == "value" or var == value
            var eqMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*==\\s*(.+)$/);
            if (eqMatch) {
                var varName = eqMatch[1];
                var compareValue = resolveValue(eqMatch[2]);
                var varValue = vars[varName];
                if (varValue === undefined || varValue === null) varValue = '';
                return String(varValue) === compareValue;
            }
            
            // Inequality: var != "value" or var != value
            var neqMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*!=\\s*(.+)$/);
            if (neqMatch) {
                var varName = neqMatch[1];
                var compareValue = resolveValue(neqMatch[2]);
                var varValue = vars[varName];
                if (varValue === undefined || varValue === null) varValue = '';
                return String(varValue) !== compareValue;
            }
            
            // Greater than: var > value
            var gtMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*>\\s*(.+)$/);
            if (gtMatch) {
                var varName = gtMatch[1];
                var compareValue = parseFloat(resolveValue(gtMatch[2]));
                var varValue = parseFloat(vars[varName] || 0);
                return varValue > compareValue;
            }
            
            // Less than: var < value
            var ltMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*<\\s*(.+)$/);
            if (ltMatch) {
                var varName = ltMatch[1];
                var compareValue = parseFloat(resolveValue(ltMatch[2]));
                var varValue = parseFloat(vars[varName] || 0);
                return varValue < compareValue;
            }
            
            // Greater or equal: var >= value
            var gteMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*>=\\s*(.+)$/);
            if (gteMatch) {
                var varName = gteMatch[1];
                var compareValue = parseFloat(resolveValue(gteMatch[2]));
                var varValue = parseFloat(vars[varName] || 0);
                return varValue >= compareValue;
            }
            
            // Less or equal: var <= value
            var lteMatch = condition.match(/^([A-Za-z_][A-Za-z0-9_.]*)\\s*<=\\s*(.+)$/);
            if (lteMatch) {
                var varName = lteMatch[1];
                var compareValue = parseFloat(resolveValue(lteMatch[2]));
                var varValue = parseFloat(vars[varName] || 0);
                return varValue <= compareValue;
            }
            
            // Just a variable name (truthy check)
            if (/^[A-Za-z_][A-Za-z0-9_.]*$/.test(condition)) {
                var value = vars[condition];
                return !!value && value !== '' && value !== '0' && value !== 'false';
            }
            
            return false;
        }
        
        // Template replacement function
        function resolveTemplate(text) {
            if (!text || typeof text !== 'string' || text.indexOf('${') === -1) {
                return text;
            }
            
            // Match ${...} expressions (including ternary)
            return text.replace(/\\$\\{([^}]+)\\}/g, function(match, expression) {
                if (!expression) return match;
                expression = expression.trim();
                if (!expression) return '';
                
                // First, check if it's a simple variable (most common case)
                if (/^[A-Za-z_][A-Za-z0-9_.]*$/.test(expression)) {
                    var value = vars[expression];
                    
                    if (value === undefined || value === null) {
                        return '';
                    }
                    
                    if (typeof value === 'boolean') {
                        return value ? 'true' : 'false';
                    }
                    
                    return String(value);
                }
                
                // Check if it's a ternary expression: condition ? trueValue : falseValue
                // Only match if there's a ? followed by : (not just any ? in the text)
                var questionIdx = expression.indexOf('?');
                var colonIdx = expression.indexOf(':');
                
                if (questionIdx > 0 && colonIdx > questionIdx) {
                    // Parse the ternary manually for more control
                    var condition = expression.substring(0, questionIdx).trim();
                    var rest = expression.substring(questionIdx + 1);
                    var restColonIdx = rest.indexOf(':');
                    
                    if (restColonIdx > 0) {
                        var trueValue = rest.substring(0, restColonIdx).trim();
                        var falseValue = rest.substring(restColonIdx + 1).trim();
                        
                        // Evaluate the condition
                        var conditionResult = evaluateCondition(condition);
                        
                        // Return the appropriate value
                        return resolveValue(conditionResult ? trueValue : falseValue);
                    }
                }
                
                // Unknown expression format - return empty string rather than broken template
                return '';
            });
        }
        
        // Walk all text nodes and resolve templates (first pass - stores originals)
        function resolveAllTemplates() {
            var walker = document.createTreeWalker(
                document.body || document.documentElement,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );
            
            var node;
            var nodesToUpdate = [];
            
            // Collect nodes first (avoid modifying while walking)
            while (node = walker.nextNode()) {
                if (node.textContent && node.textContent.indexOf('${') !== -1) {
                    nodesToUpdate.push(node);
                }
            }
            
            // Resolve templates in collected nodes
            nodesToUpdate.forEach(function(textNode) {
                var original = textNode.textContent;
                var resolved = resolveTemplate(original);
                if (resolved !== original) {
                    // Store original template for later re-resolution
                    templateStore.push({ node: textNode, original: original });
                    textNode.textContent = resolved;
                    // Process newlines after setting content
                    processTextNodeForNewlines(textNode);
                }
            });
            
            // Also resolve templates in attribute values (e.g., src, href, alt, title, placeholder)
            var attributesToCheck = ['src', 'href', 'alt', 'title', 'placeholder', 'value', 'data-text', 'class'];
            var elements = document.querySelectorAll('*');
            
            elements.forEach(function(el) {
                attributesToCheck.forEach(function(attrName) {
                    var attrValue = el.getAttribute(attrName);
                    if (attrValue && attrValue.indexOf('${') !== -1) {
                        // Store original for re-resolution
                        attrTemplateStore.push({ element: el, attr: attrName, original: attrValue });
                        el.setAttribute(attrName, resolveTemplate(attrValue));
                    }
                });
            });
        }
        
        // Re-resolve all stored templates with updated variables
        function reResolveTemplates() {
            // Re-resolve text nodes
            templateStore.forEach(function(item) {
                if (item.node && item.node.parentNode) {
                    var resolved = resolveTemplate(item.original);
                    item.node.textContent = resolved;
                    processTextNodeForNewlines(item.node);
                }
            });
            
            // Re-resolve attributes
            attrTemplateStore.forEach(function(item) {
                if (item.element && item.element.parentNode) {
                    item.element.setAttribute(item.attr, resolveTemplate(item.original));
                }
            });
        }
        
        // Convert literal \\n strings in any text node to actual line breaks
        function processTextNodeForNewlines(textNode) {
            var text = textNode.textContent;
            if (!text) return false;
            
            // Check if this text contains any newline patterns
            if (text.indexOf(BACKSLASH_N) === -1 && text.indexOf('\\n') === -1) {
                return false;
            }
            
            // First handle double-escaped (\\\\n -> \\n), then single-escaped (\\n -> newline)
            var normalizedText = text;
            // Replace double backslash-n with single backslash-n first
            while (normalizedText.indexOf(DOUBLE_BACKSLASH_N) !== -1) {
                normalizedText = normalizedText.split(DOUBLE_BACKSLASH_N).join(BACKSLASH_N);
            }
            // Then replace single backslash-n with actual newline
            normalizedText = normalizedText.split(BACKSLASH_N).join('\\n');
            
            var lines = normalizedText.split('\\n');
            
            if (lines.length > 1) {
                var fragment = document.createDocumentFragment();
                lines.forEach(function(line, index) {
                    fragment.appendChild(document.createTextNode(line));
                    if (index < lines.length - 1) {
                        fragment.appendChild(document.createElement('br'));
                    }
                });
                if (textNode.parentNode) {
                    textNode.parentNode.replaceChild(fragment, textNode);
                    return true;
                }
            }
            return false;
        }
        
        function convertNewlinesInAllText() {
            var walker = document.createTreeWalker(
                document.body || document.documentElement,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );
            
            var node;
            var nodesToProcess = [];
            
            // Collect all text nodes
            while (node = walker.nextNode()) {
                if (node.textContent && node.textContent.length > 0) {
                    nodesToProcess.push(node);
                }
            }
            
            // Process each node
            nodesToProcess.forEach(processTextNodeForNewlines);
        }
        
        // Watch for dynamically added content
        function setupNewlineObserver() {
            var observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 3) { // Text node
                            processTextNodeForNewlines(node);
                        } else if (node.nodeType === 1) { // Element node
                            var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, null, false);
                            var textNode;
                            var textNodes = [];
                            while (textNode = walker.nextNode()) {
                                textNodes.push(textNode);
                            }
                            textNodes.forEach(processTextNodeForNewlines);
                        }
                    });
                });
            });
            observer.observe(document.body || document.documentElement, {
                childList: true,
                subtree: true
            });
        }
        
        // Listen for variable updates from native side
        function setupVariableListener() {
            document.addEventListener('message', function(event) {
                try {
                    var data = event.data;
                    if (typeof data === 'string') {
                        data = JSON.parse(data);
                    }

                    if (data && data.type === 'rampkit:variables' && data.vars) {
                        // Update state variables
                        Object.keys(data.vars).forEach(function(key) {
                            stateVars[key] = data.vars[key];
                        });
                        window.__rampkitVariables = stateVars;

                        // Rebuild vars map with new values
                        rebuildVars();

                        // Re-resolve all templates
                        reResolveTemplates();

                        console.log('✅ RampKit variables updated:', Object.keys(data.vars).join(', '));
                    }
                } catch(e) {
                    // Ignore parse errors for non-JSON messages
                }
            });
        }

        // Listen for input blur events to notify native for debounce flush
        function setupBlurListener() {
            document.addEventListener('blur', function(e) {
                var target = e.target;
                if (!target) return;
                var tagName = target.tagName ? target.tagName.toUpperCase() : '';
                if (tagName !== 'INPUT' && tagName !== 'TEXTAREA') return;

                // Get variable name from data-var, name, or id attribute
                var varName = target.getAttribute('data-var') || target.name || target.id;
                if (!varName) return;

                try {
                    var message = { type: 'rampkit:input-blur', variableName: varName };
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rampkit) {
                        window.webkit.messageHandlers.rampkit.postMessage(JSON.stringify(message));
                    } else if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
                        window.ReactNativeWebView.postMessage(JSON.stringify(message));
                    }
                } catch(err) {
                    // Silently ignore messaging errors
                }
            }, true); // Use capture phase to catch all blur events
        }
        
        // Run resolution (wrapped in try-catch so rampkitUpdateVariables is always defined)
        try {
            if (document.body) {
                resolveAllTemplates();
                convertNewlinesInAllText();
                setupNewlineObserver();
                setupVariableListener();
                setupBlurListener();
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    try {
                        resolveAllTemplates();
                        convertNewlinesInAllText();
                        setupNewlineObserver();
                        setupVariableListener();
                        setupBlurListener();
                    } catch(e2) {
                        console.error('[RampKit] DOMContentLoaded resolve error:', e2);
                    }
                });
            }
        } catch(e) {
            console.error('[RampKit] Template resolve error:', e);
        }

        // Mark as resolved
        window.__rampkitTemplatesResolved = true;

        // Expose for re-running after dynamic content changes
        window.rampkitResolveTemplates = function() {
            window.__rampkitTemplatesResolved = false;
            resolveAllTemplates();
            convertNewlinesInAllText();
            window.__rampkitTemplatesResolved = true;
        };

        // Expose for updating variables programmatically
        window.rampkitUpdateVariables = function(newVars) {
            if (!newVars) return;
            Object.keys(newVars).forEach(function(key) {
                stateVars[key] = newVars[key];
            });
            window.__rampkitVariables = stateVars;
            rebuildVars();
            // If stores are empty (initial scan may have failed), re-scan DOM
            if (templateStore.length === 0 && attrTemplateStore.length === 0) {
                resolveAllTemplates();
            } else {
                reResolveTemplates();
            }
        };

        console.log('[RampKit] Templates resolved, stores: text=' + templateStore.length + ' attr=' + attrTemplateStore.length + ' vars=' + Object.keys(vars).length);
    })();
    """
    
    /// On-open action handler script
    /// Processes data-on-open-actions attributes for automatic action sequences
    /// Handles wait/delay actions with setTimeout and visibility checks
    static let onOpenActionHandler = """
    (function() {
        'use strict';

        // Skip if already applied
        if (window.__rampkitOnOpenApplied) return;
        window.__rampkitOnOpenApplied = true;

        // Helper to send message to native
        function sendMessage(data) {
            try {
                var jsonStr = JSON.stringify(data);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rampkit) {
                    window.webkit.messageHandlers.rampkit.postMessage(jsonStr);
                } else if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
                    window.ReactNativeWebView.postMessage(jsonStr);
                }
            } catch (e) {
                console.log('[RampKit] Failed to send message:', e);
            }
        }

        // Process on-open actions when screen becomes visible
        function processOnOpenActions() {
            var elements = document.querySelectorAll('[data-on-open-actions]');
            elements.forEach(function(el) {
                try {
                    var actionsStr = el.getAttribute('data-on-open-actions');
                    if (!actionsStr) return;

                    // Skip if already processed
                    if (el.hasAttribute('data-on-open-processed')) return;
                    el.setAttribute('data-on-open-processed', 'true');

                    // Decode HTML entities
                    actionsStr = actionsStr.replace(/&quot;/g, '"').replace(/&#34;/g, '"')
                                           .replace(/&apos;/g, "'").replace(/&#39;/g, "'")
                                           .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
                                           .replace(/&amp;/g, '&');

                    var actions = JSON.parse(actionsStr);
                    if (!Array.isArray(actions)) return;

                    console.log('[RampKit] Processing on-open actions:', actions.length);

                    // Execute actions in sequence with delays
                    executeActions(actions, 0);
                } catch (e) {
                    console.log('[RampKit] Failed to parse on-open-actions:', e);
                }
            });
        }

        // Execute actions recursively with delay support
        function executeActions(actionList, index) {
            if (index >= actionList.length) return;

            // CRITICAL: Stop if screen became inactive
            if (!window.__rampkitScreenVisible) {
                console.log('[RampKit] Stopping on-open actions - screen inactive');
                return;
            }

            var action = actionList[index];
            var actionType = action.type || action.actionType;

            console.log('[RampKit] Executing on-open action:', actionType);

            if (actionType === 'wait') {
                var waitMs = action.waitMs || action.duration || 1000;
                setTimeout(function() {
                    executeActions(actionList, index + 1);
                }, waitMs);
                return;
            }

            if (actionType === 'navigate' || actionType === 'continue') {
                var target = action.targetScreenId || action.target || '__continue__';
                var animation = action.animation || 'fade';
                sendMessage({
                    type: 'rampkit:navigate',
                    targetScreenId: target,
                    animation: animation,
                    fromOnOpen: true
                });
                // Don't continue to next action after navigate
                return;
            }

            if (actionType === 'goBack') {
                sendMessage({
                    type: 'rampkit:goBack',
                    animation: action.animation || 'fade',
                    fromOnOpen: true
                });
                return;
            }

            if (actionType === 'close') {
                sendMessage({ type: 'rampkit:close', fromOnOpen: true });
                return;
            }

            if (actionType === 'requestReview' || actionType === 'request-review') {
                // Prevent duplicate review requests in the same session
                if (!window.__rampkitReviewRequested) {
                    window.__rampkitReviewRequested = true;
                    sendMessage({ type: 'rampkit:request-review', fromOnOpen: true });
                } else {
                    console.log('[RampKit] Skipping duplicate review request');
                }
                executeActions(actionList, index + 1);
                return;
            }

            if (actionType === 'requestNotificationPermission' || actionType === 'request-notification-permission') {
                sendMessage({
                    type: 'rampkit:request-notification-permission',
                    ios: action.ios,
                    android: action.android,
                    behavior: action.behavior,
                    fromOnOpen: true
                });
                executeActions(actionList, index + 1);
                return;
            }

            if (actionType === 'haptic') {
                sendMessage({
                    type: 'rampkit:haptic',
                    hapticType: action.hapticType || 'impact',
                    impactStyle: action.impactStyle || 'medium',
                    notificationType: action.notificationType,
                    fromOnOpen: true
                });
                executeActions(actionList, index + 1);
                return;
            }

            if (actionType === 'setVariable') {
                if (action.key) {
                    // Update local state
                    if (window.__rampkitVars) {
                        window.__rampkitVars[action.key] = action.value;
                    }
                    if (window.__rampkitVariables) {
                        window.__rampkitVariables[action.key] = action.value;
                    }

                    // Notify native
                    var vars = {};
                    vars[action.key] = action.value;
                    if (typeof window.rampkitUpdateVariables === 'function') window.rampkitUpdateVariables(vars);
                    sendMessage({ type: 'rampkit:variables', vars: vars, fromOnOpen: true });
                }
                executeActions(actionList, index + 1);
                return;
            }

            if (actionType === 'showPaywall') {
                sendMessage({
                    type: 'rampkit:show-paywall',
                    payload: action.payload || { paywallId: action.paywallId },
                    fromOnOpen: true
                });
                return;
            }

            if (actionType === 'onboardingFinished' || actionType === 'finishOnboarding' || actionType === 'finish') {
                sendMessage({
                    type: 'rampkit:onboarding-finished',
                    payload: action.payload,
                    fromOnOpen: true
                });
                return;
            }

            // Unknown action type - continue to next
            console.log('[RampKit] Unknown on-open action type:', actionType);
            executeActions(actionList, index + 1);
        }

        // Listen for screen-visible event to trigger on-open actions
        document.addEventListener('rampkit:screen-visible', function(event) {
            console.log('[RampKit] Screen visible event received, processing on-open actions');
            // Small delay to ensure DOM is ready
            setTimeout(processOnOpenActions, 50);
        });

        // Also check if screen is already visible (for first screen)
        if (window.__rampkitScreenVisible) {
            setTimeout(processOnOpenActions, 50);
        }

        console.log('[RampKit] On-open action handler installed');
    })();
    """

    /// Comprehensive security hardening script
    /// Prevents text selection, zooming, context menus, copy/paste, drag
    /// Injected before content loads
    static let hardening = """
    (function(){
      try {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; document.head.appendChild(meta); }
        meta.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover');
        
        var style = document.createElement('style');
        style.textContent='html,body{overflow-x:hidden!important;} html,body,*{-webkit-user-select:none!important;user-select:none!important;-webkit-touch-callout:none!important;-ms-user-select:none!important;touch-action: pan-y;} *{-webkit-tap-highlight-color: rgba(0,0,0,0)!important;} ::selection{background: transparent!important;} ::-moz-selection{background: transparent!important;} a,img{-webkit-user-drag:none!important;user-drag:none!important;-webkit-touch-callout:none!important} input,textarea{caret-color:transparent!important;-webkit-user-select:none!important;user-select:none!important}';
        document.head.appendChild(style);
        
        var prevent=function(e){e.preventDefault&&e.preventDefault();};
        document.addEventListener('gesturestart',prevent,{passive:false});
        document.addEventListener('gesturechange',prevent,{passive:false});
        document.addEventListener('gestureend',prevent,{passive:false});
        document.addEventListener('dblclick',prevent,{passive:false});
        document.addEventListener('wheel',function(e){ if(e.ctrlKey) e.preventDefault(); },{passive:false});
        document.addEventListener('touchmove',function(e){ if(e.scale && e.scale !== 1) e.preventDefault(); },{passive:false});
        document.addEventListener('selectstart',prevent,{passive:false,capture:true});
        document.addEventListener('contextmenu',prevent,{passive:false,capture:true});
        document.addEventListener('copy',prevent,{passive:false,capture:true});
        document.addEventListener('cut',prevent,{passive:false,capture:true});
        document.addEventListener('paste',prevent,{passive:false,capture:true});
        document.addEventListener('dragstart',prevent,{passive:false,capture:true});
        
        var clearSel=function(){
          try{var sel=window.getSelection&&window.getSelection(); if(sel&&sel.removeAllRanges) sel.removeAllRanges();}catch(_){} };
        document.addEventListener('selectionchange',clearSel,{passive:true,capture:true});
        document.onselectstart=function(){ clearSel(); return false; };
        
        try{ document.documentElement.style.webkitUserSelect='none'; document.documentElement.style.userSelect='none'; }catch(_){ }
        try{ document.body.style.webkitUserSelect='none'; document.body.style.userSelect='none'; }catch(_){ }
        
        var __selTimer = setInterval(clearSel, 160);
        window.addEventListener('pagehide',function(){ try{ clearInterval(__selTimer); }catch(_){} });
        
        var enforceNoSelect = function(el){
          try{
            el.style && (el.style.webkitUserSelect='none', el.style.userSelect='none', el.style.webkitTouchCallout='none');
            el.setAttribute && (el.setAttribute('unselectable','on'), el.setAttribute('contenteditable','false'));
          }catch(_){}
        };
        
        try{
          var all=document.getElementsByTagName('*');
          for(var i=0;i<all.length;i++){ enforceNoSelect(all[i]); }
          
          var obs = new MutationObserver(function(muts){
            for(var j=0;j<muts.length;j++){
              var m=muts[j];
              if(m.type==='childList'){
                m.addedNodes && m.addedNodes.forEach && m.addedNodes.forEach(function(n){ 
                  if(n && n.nodeType===1){ 
                    enforceNoSelect(n); 
                    var q=n.getElementsByTagName? n.getElementsByTagName('*'): []; 
                    for(var k=0;k<q.length;k++){ enforceNoSelect(q[k]); }
                  }
                });
              } else if(m.type==='attributes'){
                enforceNoSelect(m.target);
              }
            }
          });
          obs.observe(document.documentElement,{ childList:true, subtree:true, attributes:true, attributeFilter:['contenteditable','style'] });
        }catch(_){ }
      } catch(_) {}
    })(); true;
    """
    
    /// Translation script for localized content
    /// Replaces text content in elements with data-ramp-id attributes
    /// Supports RTL languages (Arabic, Hebrew, Persian, Urdu)
    static let translationScript = """
    (function() {
        var RTL_LANGUAGES = ['ar', 'he', 'fa', 'ur'];

        function applyTranslations(translations, locale, language) {
            if (!translations || typeof translations !== 'object') return;

            // Fallback chain: exact locale -> language code -> nothing
            var t = translations[locale] || translations[language] || null;
            if (!t) return;

            // Apply RTL if needed
            if (RTL_LANGUAGES.indexOf(language) !== -1) {
                document.documentElement.setAttribute('dir', 'rtl');
                document.documentElement.setAttribute('lang', language);
            }

            // Replace text content by data-ramp-id
            Object.keys(t).forEach(function(id) {
                var el = document.querySelector('[data-ramp-id="' + id + '"]');
                if (el) {
                    el.textContent = t[id];
                }
            });
        }

        // Expose for immediate call
        window.__rampkitApplyTranslations = applyTranslations;
    })();
    """

    /// Lightweight no-select script
    /// Injected after content loads (idempotent)
    static let noSelect = """
    (function(){
      try {
        if (window.__rkNoSelectApplied) return true;
        window.__rkNoSelectApplied = true;
        
        var style = document.getElementById('rk-no-select-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'rk-no-select-style';
          style.innerHTML = "\\n        * {\\n          user-select: none !important;\\n          -webkit-user-select: none !important;\\n          -webkit-touch-callout: none !important;\\n        }\\n        ::selection {\\n          background: transparent !important;\\n        }\\n      ";
          document.head.appendChild(style);
        }
        
        var prevent = function(e){ if(e && e.preventDefault) e.preventDefault(); return false; };
        document.addEventListener('contextmenu', prevent, { passive: false, capture: true });
        document.addEventListener('selectstart', prevent, { passive: false, capture: true });
      } catch (_) {}
      true;
    })();
    """
}



