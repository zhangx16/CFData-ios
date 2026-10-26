// Package mobile exposes only simple types supported by gomobile bindings.
package mobile

import "cfdataios/internal/core"

// Start starts the in-process backend and returns its authenticated local URL.
func Start(dataDirectory string) (string, error) { return core.MobileStart(dataDirectory) }

// Pause cancels active scans when iOS backgrounds the application.
func Pause() { core.MobilePause() }

// Resume allows the user to start new foreground tasks.
func Resume() { core.MobileResume() }
