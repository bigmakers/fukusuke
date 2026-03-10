const { app, BrowserWindow, dialog } = require('electron');
const path = require('path');

// Single instance lock
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
}

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 480,
    height: 850,
    minWidth: 380,
    minHeight: 600,
    title: '福助',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile('index.html');

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// Handle calday:// URL scheme
function handleCalDayUrl(url) {
  if (!url) return;
  const match = url.match(/calday:\/\/import\?data=([A-Za-z0-9+/=]+)/);
  if (match && mainWindow) {
    const data = match[1];
    mainWindow.webContents.executeJavaScript(
      `if (typeof window.importFromURL === 'function') { window.importFromURL('${data}'); }`
    );
  }
}

// Register URL scheme (Windows)
if (process.defaultApp) {
  if (process.argv.length >= 2) {
    app.setAsDefaultProtocolClient('calday', process.execPath, [path.resolve(process.argv[1])]);
  }
} else {
  app.setAsDefaultProtocolClient('calday');
}

app.whenReady().then(() => {
  createWindow();

  // Check if launched with URL scheme argument
  const urlArg = process.argv.find(arg => arg.startsWith('calday://'));
  if (urlArg) {
    // Wait for page to load
    mainWindow.webContents.on('did-finish-load', () => {
      handleCalDayUrl(urlArg);
    });
  }
});

// Handle second instance (URL scheme on Windows when app is already running)
app.on('second-instance', (event, commandLine) => {
  const url = commandLine.find(arg => arg.startsWith('calday://'));
  if (url) {
    handleCalDayUrl(url);
  }
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
});

app.on('window-all-closed', () => {
  app.quit();
});

app.on('activate', () => {
  if (mainWindow === null) createWindow();
});
