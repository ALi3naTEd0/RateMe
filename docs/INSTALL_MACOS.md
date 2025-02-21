# Installing Rate Me on macOS

## Installation Steps

1. Download the RateMe-Debug.zip file
2. Double-click the zip file to extract it
3. Drag and drop the "Rate Me.app" to your Applications folder
4. The first time you run the app:
   - Right-click (or Control-click) on the app
   - Select "Open" from the menu
   - Click "Open" in the security dialog
   - The app will now open normally for future launches

## Note About Security

Since this is an unsigned build, macOS will show a security warning on first launch. This is normal and you can safely run the app after following the steps above.

## Troubleshooting

If you get a "App is damaged" message:
1. Open Terminal
2. Run: `xattr -cr "/Applications/Rate Me.app"`
3. Try launching the app again
