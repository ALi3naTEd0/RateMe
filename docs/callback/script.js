document.addEventListener('DOMContentLoaded', function() {
    // Show status
    const statusEl = document.getElementById('status');
    const debugEl = document.getElementById('debug');
    
    // Function to log message to page for debugging
    function logDebug(message) {
        console.log(message);
        if (debugEl) {
            debugEl.innerHTML += message + '<br>';
            debugEl.style.display = 'block'; // Make debug info visible
        }
    }
    
    // Function to update status message
    function updateStatus(message) {
        if (statusEl) {
            statusEl.textContent = message;
        }
    }
    
    // Function to handle the auth code flow response
    function handleAuthCodeResponse() {
        try {
            // Check for authorization code in URL parameters
            const urlParams = new URLSearchParams(window.location.search);
            const authCode = urlParams.get('code');
            const state = urlParams.get('state');
            
            if (authCode) {
                logDebug('Found authorization code: ' + authCode.substring(0, 10) + '...');
                
                return {
                    responseType: 'code',
                    code: authCode,
                    state: state
                };
            }
            
            // Check for error in URL parameters
            const error = urlParams.get('error');
            if (error) {
                logDebug('Error from authorization server: ' + error);
                return {
                    responseType: 'error',
                    error: error
                };
            }
            
            return null;
        } catch (e) {
            logDebug('Error handling auth code response: ' + e.toString());
            return null;
        }
    }
    
    // Function to extract access token from URL hash (for backward compatibility)
    function handleImplicitFlowResponse() {
        try {
            logDebug('Checking URL hash: ' + window.location.hash);
            
            if (window.location.hash.length > 0) {
                // Remove the leading # and split by &
                const params = new URLSearchParams(window.location.hash.substring(1));
                
                // Extract access token
                const accessToken = params.get('access_token');
                const expiresIn = params.get('expires_in');
                const state = params.get('state');
                
                if (accessToken) {
                    logDebug('Found access token: ' + accessToken.substring(0, 10) + '...');
                    
                    // Save to local storage for debug purposes
                    localStorage.setItem('spotify_access_token', accessToken);
                    
                    // Calculate expiry time
                    const expiryTime = new Date();
                    expiryTime.setSeconds(expiryTime.getSeconds() + parseInt(expiresIn || '3600'));
                    localStorage.setItem('spotify_token_expiry', expiryTime.toISOString());
                    
                    // Return token
                    return {
                        responseType: 'token',
                        accessToken: accessToken,
                        expiresIn: expiresIn || '3600', // Default to 1 hour if not provided
                        state: state,
                        expiryTime: expiryTime.toISOString()
                    };
                }
            }
            
            return null;
        } catch (e) {
            logDebug('Error handling implicit flow response: ' + e.toString());
            return null;
        }
    }
    
    // Function to redirect back to app with either code or token
    function redirectToApp(authResponse) {
        logDebug('Redirecting to app with auth response type: ' + authResponse.responseType);
        
        // Build the right redirect URI based on response type
        let redirectUriBase;
        let redirectParams;
        
        if (authResponse.responseType === 'code') {
            // Auth code flow
            redirectUriBase = 'rateme://spotify-callback';
            redirectParams = `?code=${encodeURIComponent(authResponse.code)}`;
            if (authResponse.state) {
                redirectParams += `&state=${encodeURIComponent(authResponse.state)}`;
            }
        } else if (authResponse.responseType === 'token') {
            // Implicit flow (token directly in URL)
            redirectUriBase = 'rateme://spotify-callback';
            redirectParams = `?access_token=${encodeURIComponent(authResponse.accessToken)}&expires_in=${authResponse.expiresIn}`;
            if (authResponse.state) {
                redirectParams += `&state=${encodeURIComponent(authResponse.state)}`;
            }
        } else {
            // Error case
            redirectUriBase = 'rateme://spotify-callback';
            redirectParams = `?error=${encodeURIComponent(authResponse.error || 'unknown_error')}`;
        }
        
        // List of schemes to try for redirect back to app
        const redirectSchemes = [
            `${redirectUriBase}${redirectParams}`,
            `com.ali3nated0.rateme://spotify-callback${redirectParams}`,
            `com.rateme.app://spotify-callback${redirectParams}`
        ];
        
        // Log all redirect attempts for debugging
        logDebug('Attempting redirects with schemes: ' + JSON.stringify(redirectSchemes));
        
        let currentSchemeIndex = 0;
        
        // Add support for XDG on Linux with xdg-open
        const xdgRedirectUrl = `xdg-open:${redirectUriBase}${redirectParams}`;
        
        function tryNextScheme() {
            if (currentSchemeIndex < redirectSchemes.length) {
                const scheme = redirectSchemes[currentSchemeIndex];
                logDebug(`Attempting redirect with scheme ${currentSchemeIndex + 1}/${redirectSchemes.length}: ${scheme}`);
                
                // Create an iframe for the redirect to avoid losing this page
                const iframe = document.createElement('iframe');
                iframe.style.display = 'none';
                iframe.src = scheme;
                document.body.appendChild(iframe);
                
                // Also try direct location change on the first attempt
                if (currentSchemeIndex === 0) {
                    try {
                        // Attempt direct location change (works in some browsers)
                        setTimeout(() => {
                            // Use a timeout to allow both methods to attempt
                            if (document.visibilityState !== 'hidden') {
                                window.location.href = scheme;
                            }
                        }, 200);
                    } catch (e) {
                        logDebug('Error with direct location change: ' + e);
                    }
                }
                
                // Wait and try the next scheme if this one didn't work
                currentSchemeIndex++;
                setTimeout(tryNextScheme, 800); // Increased delay for better reliability
            } else {
                // Try XDG-open for Linux specifically
                logDebug('Trying XDG-open method for Linux: ' + xdgRedirectUrl);
                try {
                    window.location.href = xdgRedirectUrl;
                    // Give the XDG-open a chance to work
                    setTimeout(() => {
                        if (document.visibilityState !== 'hidden') {
                            // We've tried all schemes, show manual instructions
                            logDebug("All automatic redirect attempts failed. Showing manual instructions.");
                            showManualInstructions(authResponse);
                        }
                    }, 1000);
                } catch (e) {
                    logDebug("Error with XDG redirect: " + e);
                    showManualInstructions(authResponse);
                }
            }
        }
        
        // Start trying schemes
        tryNextScheme();
    }
    
    // Function to show manual instructions if auto-redirect fails
    function showManualInstructions(authResponse) {
        updateStatus('Please copy this code to the app');
        document.querySelector('.spinner').style.display = 'none';
        
        // Create manual instructions
        const container = document.getElementById('container');
        if (container) {
            // Keep existing heading but clear other content
            const heading = container.querySelector('h1');
            container.innerHTML = '';
            if (heading) container.appendChild(heading);
            
            // Create new content
            const header = document.createElement('h2');
            header.textContent = 'Manual Authentication';
            container.appendChild(header);
            
            const instructions = document.createElement('p');
            
            // Different instructions based on auth type
            if (authResponse.responseType === 'code') {
                instructions.textContent = 'Please return to RateMe app and enter this authorization code manually:';
                container.appendChild(instructions);
                
                const codeDisplay = document.createElement('div');
                codeDisplay.classList.add('token-display');
                codeDisplay.textContent = authResponse.code;
                container.appendChild(codeDisplay);
                
                const copyButton = document.createElement('button');
                copyButton.textContent = 'Copy Code';
                copyButton.classList.add('copy-button');
                copyButton.addEventListener('click', function() {
                    copyToClipboard(authResponse.code, copyButton);
                });
                container.appendChild(copyButton);
                
                const note = document.createElement('p');
                note.classList.add('expiry-info');
                note.textContent = 'Note: This code will expire in 10 minutes. Complete authentication in the app promptly.';
                container.appendChild(note);
            } else if (authResponse.responseType === 'token') {
                // For backward compatibility with token flow
                instructions.textContent = 'Please return to RateMe app and enter this access token manually:';
                container.appendChild(instructions);
                
                const tokenDisplay = document.createElement('div');
                tokenDisplay.classList.add('token-display');
                tokenDisplay.textContent = authResponse.accessToken;
                container.appendChild(tokenDisplay);
                
                const copyButton = document.createElement('button');
                copyButton.textContent = 'Copy Token';
                copyButton.classList.add('copy-button');
                copyButton.addEventListener('click', function() {
                    copyToClipboard(authResponse.accessToken, copyButton);
                });
                container.appendChild(copyButton);
                
                const expiryInfo = document.createElement('p');
                expiryInfo.classList.add('expiry-info');
                const expiryDate = new Date(authResponse.expiryTime);
                const expiryHours = Math.round(authResponse.expiresIn / 3600);
                expiryInfo.textContent = `Token expires in approximately ${expiryHours} hours (${expiryDate.toLocaleString()})`;
                container.appendChild(expiryInfo);
            } else {
                // Error case
                instructions.textContent = 'Authentication error. Please try again in the app.';
                instructions.style.color = 'red';
                container.appendChild(instructions);
                
                const errorDisplay = document.createElement('div');
                errorDisplay.classList.add('error-display');
                errorDisplay.textContent = authResponse.error || 'Unknown error';
                container.appendChild(errorDisplay);
            }
            
            // Add app return buttons for different platforms
            const returnButtonsContainer = document.createElement('div');
            returnButtonsContainer.classList.add('return-buttons');
            
            const returnButton = document.createElement('button');
            returnButton.textContent = 'Return to RateMe App';
            returnButton.classList.add('return-button');
            returnButton.addEventListener('click', function() {
                window.location.href = 'rateme://spotify-callback';
            });
            returnButtonsContainer.appendChild(returnButton);
            
            container.appendChild(returnButtonsContainer);
            
            // Show debug toggle
            const debugToggle = document.createElement('div');
            debugToggle.classList.add('debug-toggle');
            debugToggle.textContent = 'Show debug info';
            debugToggle.addEventListener('click', function() {
                debugEl.style.display = debugEl.style.display === 'none' ? 'block' : 'none';
            });
            container.appendChild(debugToggle);
            
            // Add the debug element back
            container.appendChild(debugEl);
        }
    }
    
    function copyToClipboard(text, button) {
        navigator.clipboard.writeText(text)
            .then(() => {
                button.textContent = 'Copied!';
                setTimeout(() => {
                    button.textContent = button.textContent.includes('Code') ? 'Copy Code' : 'Copy Token';
                }, 2000);
            })
            .catch(err => {
                logDebug('Failed to copy: ' + err);
                // Fallback for browsers that don't support clipboard API
                const textArea = document.createElement('textarea');
                textArea.value = text;
                textArea.style.position = 'fixed';
                document.body.appendChild(textArea);
                textArea.focus();
                textArea.select();
                try {
                    document.execCommand('copy');
                    button.textContent = 'Copied!';
                    setTimeout(() => {
                        button.textContent = button.textContent.includes('Code') ? 'Copy Code' : 'Copy Token';
                    }, 2000);
                } catch (e) {
                    logDebug('Fallback copy method failed: ' + e);
                }
                document.body.removeChild(textArea);
            });
    }
    
    // Main function - process the authentication result
    function processAuthResult() {
        // First try auth code flow (preferred)
        const authCodeResponse = handleAuthCodeResponse();
        if (authCodeResponse) {
            updateStatus('Authentication successful! Redirecting back to app...');
            redirectToApp(authCodeResponse);
            return;
        }
        
        // Then try implicit flow (backward compatibility)
        const implicitFlowResponse = handleImplicitFlowResponse();
        if (implicitFlowResponse) {
            updateStatus('Authentication successful! Redirecting back to app...');
            redirectToApp(implicitFlowResponse);
            return;
        }
        
        // Check if error parameter exists
        const urlParams = new URLSearchParams(window.location.search);
        const error = urlParams.get('error');
        
        if (error) {
            updateStatus(`Authentication error: ${error}. Please try again.`);
            logDebug(`Error from authentication: ${error}`);
            redirectToApp({responseType: 'error', error: error});
            document.querySelector('.spinner').style.display = 'none';
        } else {
            updateStatus('No authentication data found. Please try again.');
            logDebug('No token or error found in URL');
            document.querySelector('.spinner').style.display = 'none';
        }
    }
    
    // Start processing
    processAuthResult();
});
