// Lifecycle hooks are separate from the page so UIKit can invoke them reliably.
window.cfdataDidForeground = () => window.CFData?.didForeground();
window.cfdataWillBackground = () => window.CFData?.willBackground();
