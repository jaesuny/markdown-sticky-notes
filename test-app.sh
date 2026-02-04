#!/bin/bash

# Simple test script to verify the app works

echo "🧪 Testing StickyNotes.app..."
echo ""

# Check if app exists
if [ ! -d "build/StickyNotes.app" ]; then
    echo "❌ App bundle not found. Run ./build-app.sh first."
    exit 1
fi

echo "✅ App bundle exists"

# Check if executable exists
if [ ! -f "build/StickyNotes.app/Contents/MacOS/StickyNotes" ]; then
    echo "❌ App executable not found"
    exit 1
fi

echo "✅ App executable exists"

# Check if resources exist
if [ ! -d "build/StickyNotes.app/Contents/Resources" ]; then
    echo "❌ Resources directory not found"
    exit 1
fi

echo "✅ Resources directory exists"

# Check if HTML editor exists
if [ ! -f "build/StickyNotes.app/Contents/Resources/Editor/index.html" ]; then
    echo "❌ Editor HTML not found"
    exit 1
fi

echo "✅ Editor HTML exists"

# Check if Info.plist exists
if [ ! -f "build/StickyNotes.app/Contents/Info.plist" ]; then
    echo "❌ Info.plist not found"
    exit 1
fi

echo "✅ Info.plist exists"

echo ""
echo "🎉 All basic checks passed!"
echo ""
echo "To launch the app:"
echo "  open build/StickyNotes.app"
echo ""
echo "The app should:"
echo "  1. Create a default welcome note on first launch"
echo "  2. Display a floating window (always on top)"
echo "  3. Allow text editing in the textarea"
echo "  4. Auto-save content changes"
echo "  5. Persist window position and size"
echo "  6. Support Cmd+N to create new notes"
echo ""
