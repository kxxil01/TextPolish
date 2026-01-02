// TextPolish Landing Page JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Smooth scrolling for navigation links
    const navLinks = document.querySelectorAll('a[href^="#"]');
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const targetId = this.getAttribute('href');
            const targetElement = document.querySelector(targetId);
            
            if (targetElement) {
                const navHeight = document.querySelector('.nav').offsetHeight;
                const targetPosition = targetElement.offsetTop - navHeight - 20;
                
                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });

    // Navbar background on scroll (dark theme)
    const nav = document.querySelector('.nav');
    window.addEventListener('scroll', function() {
        if (window.scrollY > 50) {
            nav.style.background = 'rgba(13, 17, 23, 0.95)';
            nav.style.boxShadow = '0 2px 20px rgba(0, 0, 0, 0.3)';
        } else {
            nav.style.background = 'transparent';
            nav.style.boxShadow = 'none';
        }
    });

    // Intersection Observer for animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, observerOptions);

    // Observe elements for animation
    const animatedElements = document.querySelectorAll('.feature-card, .step, .download-card');
    animatedElements.forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });

    // Download button tracking
    const downloadButtons = document.querySelectorAll('.btn[href*="github.com"]');
    downloadButtons.forEach(button => {
        button.addEventListener('click', function() {
            // Track download clicks (you can integrate with analytics here)
            console.log('Download clicked:', this.textContent.trim());
            
            // Add a small delay to show feedback
            const originalText = this.innerHTML;
            this.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22A10,10 0 0,1 2,12A10,10 0 0,1 12,2M11,16.5L6.5,12L7.91,10.59L11,13.67L16.59,8.09L18,9.5L11,16.5Z"/></svg>Opening GitHub...';
            
            setTimeout(() => {
                this.innerHTML = originalText;
            }, 2000);
        });
    });

    // Demo text animation - highlight before/after alternately
    function animateDemo() {
        const wrongText = document.querySelector('.demo-wrong');
        const correctText = document.querySelector('.demo-correct');

        if (wrongText && correctText) {
            // Highlight "before" state
            wrongText.style.opacity = '1';
            correctText.style.opacity = '0.5';

            setTimeout(() => {
                // Highlight "after" state
                wrongText.style.opacity = '0.5';
                correctText.style.opacity = '1';
            }, 3000);
        }
    }

    // Start demo animation
    setTimeout(animateDemo, 1000);
    setInterval(animateDemo, 6000);

    // Keyboard shortcut display enhancement
    const shortcuts = document.querySelectorAll('.shortcut kbd');
    shortcuts.forEach(kbd => {
        kbd.addEventListener('mouseenter', function() {
            this.style.transform = 'scale(1.05)';
            this.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.2)';
        });
        
        kbd.addEventListener('mouseleave', function() {
            this.style.transform = 'scale(1)';
            this.style.boxShadow = '0 2px 4px rgba(0, 0, 0, 0.1)';
        });
    });

    // Mobile menu toggle (if needed)
    const mobileMenuButton = document.querySelector('.mobile-menu-button');
    const mobileNavLinks = document.querySelector('.nav-links');
    
    if (mobileMenuButton && mobileNavLinks) {
        mobileMenuButton.addEventListener('click', function() {
            mobileNavLinks.classList.toggle('mobile-open');
        });
    }

    // Copy to clipboard functionality for code blocks
    const codeBlocks = document.querySelectorAll('.homebrew-code code');
    codeBlocks.forEach(code => {
        code.style.cursor = 'pointer';
        code.title = 'Click to copy';

        code.addEventListener('click', function() {
            navigator.clipboard.writeText(this.textContent).then(() => {
                const originalText = this.textContent;
                this.textContent = 'Copied!';
                this.style.background = 'rgba(166, 227, 161, 0.3)';
                this.style.color = '#a6e3a1';

                setTimeout(() => {
                    this.textContent = originalText;
                    this.style.background = '';
                    this.style.color = '';
                }, 2000);
            });
        });
    });

    // Card hover effects (handled by CSS, but keeping for potential future use)
    const cards = document.querySelectorAll('.card');
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            // Hover handled by CSS
        });

        card.addEventListener('mouseleave', function() {
            // Hover handled by CSS
        });
    });

    // Download card interactions
    const downloadCards = document.querySelectorAll('.download-card');
    downloadCards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            const icon = this.querySelector('.download-icon');
            if (icon) {
                icon.style.transform = 'scale(1.1) rotate(5deg)';
            }
        });
        
        card.addEventListener('mouseleave', function() {
            const icon = this.querySelector('.download-icon');
            if (icon) {
                icon.style.transform = 'scale(1) rotate(0deg)';
            }
        });
    });

    // Parallax effect for hero section
    window.addEventListener('scroll', function() {
        const scrolled = window.pageYOffset;
        const hero = document.querySelector('.hero');
        const heroVisual = document.querySelector('.hero-visual');
        
        if (hero && heroVisual && scrolled < hero.offsetHeight) {
            const rate = scrolled * -0.5;
            heroVisual.style.transform = `translateY(${rate}px)`;
        }
    });

    // Add loading state management
    window.addEventListener('load', function() {
        document.body.classList.add('loaded');
        
        // Trigger initial animations
        setTimeout(() => {
            const heroContent = document.querySelector('.hero-content');
            if (heroContent) {
                heroContent.style.opacity = '1';
                heroContent.style.transform = 'translateY(0)';
            }
        }, 100);
    });

    // Error handling for external links
    const externalLinks = document.querySelectorAll('a[target="_blank"]');
    externalLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            // Add analytics tracking here if needed
            console.log('External link clicked:', this.href);
        });
    });

    // Performance monitoring
    if ('performance' in window) {
        window.addEventListener('load', function() {
            setTimeout(() => {
                const perfData = performance.getEntriesByType('navigation')[0];
                console.log('Page load time:', perfData.loadEventEnd - perfData.loadEventStart, 'ms');
            }, 0);
        });
    }
});

// Utility functions
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Export for potential module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        debounce
    };
}
