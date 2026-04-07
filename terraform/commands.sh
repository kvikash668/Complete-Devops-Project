#!/bin/bash
set -e

echo "===== SYSTEM UPDATE ====="
sudo apt-get update -y

echo "===== INSTALL DEPENDENCIES ====="
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https

##################################
# DOCKER INSTALLATION
##################################
echo "===== INSTALL DOCKER ====="
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu

##################################
# JENKINS INSTALLATION (FIXED)
##################################
echo "===== INSTALL JENKINS ====="

# Add Jenkins key (correct method)
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Add Jenkins repo
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Java (required)
sudo apt-get install -y openjdk-17-jdk

# Update and install Jenkins
sudo apt-get update -y
sudo apt-get install -y jenkins

# Start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

##################################
# TRIVY INSTALLATION (FIXED)
##################################
echo "===== INSTALL TRIVY ====="

# Add Trivy key
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg

# Add correct repo (IMPORTANT FIX: 'generic main')
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y trivy

##################################
# SONARQUBE (LIGHTWEIGHT DOCKER)
##################################
echo "===== RUN SONARQUBE ====="

sudo docker run -d \
  --name sonarqube \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  sonarqube:lts-community

##################################
# FINAL INFO
##################################
echo "===== SETUP COMPLETE ====="
echo "Jenkins: http://<EC2-IP>:8080"
echo "SonarQube: http://<EC2-IP>:9000"