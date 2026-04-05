#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Exchange Back-End..."
cd exchange-back-end
./mvnw clean package -DskipTests
cd ..

echo "Building Broker Back-End..."
cd broker-back-end
./mvnw clean package -DskipTests
cd ..

echo "Building Exchange Front-End..."
cd exchange-front-end
npm install
npm run build
cd ..

echo "Building Broker Front-End..."
cd broker-front-end
npm install
npm run build
cd ..

echo "Build complete!"
