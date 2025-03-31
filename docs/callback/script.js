document.addEventListener('DOMContentLoaded', function() {
    // Show status
    const statusEl = document.getElementById('status');
    const debugEl = document.getElementById('debug');
    
    // Function to log message to page for debugging
    function logDebug(message) {
        console.log(message);
        if (debugEl) {
            debugEl.innerHTML += message + '<br>';
        }
    }
    
    // Function to update status message
    function updateStatus(message) {
        if (statusEl) {
            statusEl.textContent = message;
        }
    }
    
    // Function to extract access token from URL hash
    function getTokenFromHash() {
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
                    
                    // Save to local storage for demo purposes
                    // In a real app, this would be communicated back to the app
                    localStorage.setItem('spotify_access_token', accessToken);
                    
                    // Calculate expiry time
                    const expiryTime = new Date();
                    expiryTime.setSeconds(expiryTime.getSeconds() + parseInt(expiresIn || '3600'));
                    localStorage.setItem('spotify_token_expiry', expiryTime.toISOString());
                    
                    // Return token
                    return {
                        accessToken: accessToken,
                        expiresIn: expiresIn,
                        state: state,
                        expiryTime: expiryTime.toISOString()
                    };
                } else {
                    logDebug('No access token found in URL hash');
                    return null;
                }
            } else {
                logDebug('No URL hash present');
                return null;
            }
        } catch (e) {
            logDebug('Error extracting token: ' + e.toString());
            return null;
        }
    }
    
    // Function to try various redirect methods
    function redirectToApp(token) {
        const redirectSchemes = [
            `rateme://callback?access_token=${token.accessToken}&expires_in=${token.expiresIn}&expiry_time=${encodeURIComponent(token.expiryTime)}`,
            `com.ali3nated0.rateme://callback?access_token=${token.accessToken}&expires_in=${token.expiresIn}&expiry_time=${encodeURIComponent(token.expiryTime)}`
        ];
        
        let currentSchemeIndex = 0;
        
        function tryNextScheme() {
            if (currentSchemeIndex < redirectSchemes.length) {
                const scheme = redirectSchemes[currentSchemeIndex];
                logDebug(`Attempting redirect with scheme ${currentSchemeIndex + 1}/${redirectSchemes.length}: ${scheme}`);
                
                // Try to launch the app with the current scheme
                window.location.href = scheme;
                
                // Wait and try the next scheme if this one didn't work
                currentSchemeIndex++;
                setTimeout(tryNextScheme, 300);
            } else {
                // We've tried all schemes, show manual instructions
                showManualInstructions(token);
            }
        }
        
        // Start trying schemes
        tryNextScheme();
    }
    
    // Function to show manual instructions if auto-redirect fails
    function showManualInstructions(token) {
        updateStatus('Automatic redirect failed');
        
        // Create manual instructions
        const container = document.getElementById('container');
        if (container) {
            // Clear existing content
            container.innerHTML = '';
            
            // Create new content
            const header = document.createElement('h2');
            header.textContent = 'Manual Authentication';
            container.appendChild(header);
            
            const instructions = document.createElement('p');
            instructions.textContent = 'Please return to RateMe app and enter this token manually:';
            container.appendChild(instructions);
            
            const tokenDisplay = document.createElement('div');
            tokenDisplay.classList.add('token-display');
            tokenDisplay.textContent = token.accessToken;
            container.appendChild(tokenDisplay);
            
            const copyButton = document.createElement('button');
            copyButton.textContent = 'Copy Token';
            copyButton.classList.add('copy-button');
            copyButton.addEventListener('click', function() {
                navigator.clipboard.writeText(token.accessToken)
                    .then(() => {
                        copyButton.textContent = 'Copied!';
                        setTimeout(() => {
                            copyButton.textContent = 'Copy Token';
                        }, 2000);
                    })
                    .catch(err => {
                        console.error('Failed to copy: ', err);
                    });
            });
            container.appendChild(copyButton);
            
            const expiryInfo = document.createElement('p');
            expiryInfo.classList.add('expiry-info');
            expiryInfo.textContent = `Token expires: ${new Date(token.expiryTime).toLocaleString()}`;
            container.appendChild(expiryInfo);
            
            const returnButton = document.createElement('a');
            returnButton.href = 'rateme://callback';
            returnButton.textContent = 'Return to RateMe App';
            returnButton.classList.add('return-button');
            container.appendChild(returnButton);
        }
    }
    
    // Main function - process the authentication result
    function processAuthResult() {
        const token = getTokenFromHash();
        
        if (token) {
            updateStatus('Authentication successful! Redirecting back to app...');
            redirectToApp(token);
        } else {
            // Check if error parameter exists
            const urlParams = new URLSearchParams(window.location.search);
            const error = urlParams.get('error');
            
            if (error) {
                updateStatus(`Authentication error: ${error}. Please try again.`);
                logDebug(`Error from authentication: ${error}`);
            } else {
                updateStatus('No authentication data found. Please try again.');
                logDebug('No token or error found in URL');
            }
        }
    }
    
    // Start processing
    processAuthResult();
});
