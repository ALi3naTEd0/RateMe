document.addEventListener('DOMContentLoaded', function() {
    // Fetch latest release info from GitHub API
    fetch('https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest')
        .then(response => response.json())
        .then(data => {
            // Update version number
            document.getElementById('current-version').textContent = data.tag_name.replace('v', '');
            
            // Format and update release date
            const releaseDate = new Date(data.published_at);
            const options = { month: 'long', year: 'numeric' };
            document.getElementById('release-date').textContent = releaseDate.toLocaleDateString('en-US', options);
        })
        .catch(error => {
            console.error('Error fetching release info:', error);
        });
    
    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            
            const targetId = this.getAttribute('href');
            const targetElement = document.querySelector(targetId);
            
            if (targetElement) {
                window.scrollTo({
                    top: targetElement.offsetTop - 80,
                    behavior: 'smooth'
                });
            }
        });
    });
});
