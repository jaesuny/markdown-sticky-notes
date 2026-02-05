const path = require('path');

module.exports = {
  mode: 'production',
  entry: './src/editor.js',
  output: {
    filename: 'editor.bundle.js',
    path: path.resolve(__dirname, 'dist'),
  },
  optimization: {
    splitChunks: false, // Disable code splitting - keep everything in one bundle
    runtimeChunk: false, // Don't extract runtime
    minimize: true,
  },
  module: {
    rules: [
      {
        test: /\.css$/i,
        use: ['style-loader', 'css-loader'],
      },
      {
        test: /\.(woff|woff2|ttf|eot)$/,
        type: 'asset/inline', // Inline fonts as base64 instead of separate files
      },
    ],
  },
  performance: {
    maxAssetSize: 5000000, // 5MB - increased for single bundle with inline fonts
    maxEntrypointSize: 5000000,
  },
};
