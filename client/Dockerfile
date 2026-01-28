
FROM node:18-alpine AS build

# Set working directory
WORKDIR /app

# Copy dependency files
COPY package*.json ./

# Install dependencies (clean, reproducible install)
RUN npm ci

# Add Babel plugin (for CRA compatibility with private props)
RUN npm install --save-dev @babel/plugin-proposal-private-property-in-object

# Copy source code
COPY . .

# Build production assets
RUN npm run build



FROM nginx:alpine

# Copy built static files from build stage
COPY --from=build /app/build /usr/share/nginx/html

# Remove default nginx config and replace with a custom one
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start Nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]