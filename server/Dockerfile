# ---- Stage 1: Build dependencies ----
FROM node:18-alpine AS build

# Set working directory
WORKDIR /usr/src/app

# Copy dependency files first (for better caching)
COPY package*.json ./

# Install all dependencies (including dev)
RUN npm install

# Copy the application code
COPY . .

# ---- Stage 2: Production runtime ----
FROM node:18-alpine

# Set working directory
WORKDIR /usr/src/app

# Copy only production dependencies from the build stage
COPY --from=build /usr/src/app/node_modules ./node_modules

# Copy source code from build stage
COPY --from=build /usr/src/app ./

# Expose port (backend runs on 4000)
EXPOSE 4000

# Set environment variable for production
ENV NODE_ENV=production

# Start the app using npm production script
CMD ["npm", "run", "production"]