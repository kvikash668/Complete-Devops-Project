#!/bin/bash
set -e

echo "===== SYSTEM UPDATE ====="
sudo apt-get update -y

##################################
# INSTALL JAVA FIRST (CRITICAL)
##################################
echo "===== INSTALL JAVA ====="
sudo apt-get install -y openjdk-17-jdk

##################################
# INSTALL DEPENDENCIES
##################################
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

# Fix Docker permission (IMPORTANT)
sudo usermod -aG docker ubuntu

##################################
# JENKINS INSTALLATION
##################################
echo "===== INSTALL JENKINS ====="

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y jenkins

sudo systemctl enable jenkins
sudo systemctl start jenkins

##################################
# NODEJS (FOR YOUR PIPELINE)
##################################
echo "===== INSTALL NODEJS ====="
sudo apt-get install -y nodejs npm

##################################
# TRIVY INSTALLATION
##################################
echo "===== INSTALL TRIVY ====="

curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y trivy

##################################
# SONARQUBE (SAFE RUN)
##################################
echo "===== RUN SONARQUBE ====="

if [ "$(sudo docker ps -aq -f name=sonarqube)" ]; then
  echo "SonarQube container exists. Starting..."
  sudo docker start sonarqube || true
else
  sudo docker run -d \
    --name sonarqube \
    -p 9000:9000 \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    sonarqube:lts-community
fi

sudo usermod -aG docker ubuntu
sudo systemctl restart jenkins
##################################
# FINAL INFO
##################################
echo "===== SETUP COMPLETE ====="
echo "Jenkins: http://<EC2-IP>:8080"
echo "SonarQube: http://<EC2-IP>:9000"
echo "IMPORTANT:Please Re-login required for Docker permissions|| After login run sudo usermod -aG docker ubuntu ,sudo systemctl restart jenkins , docker ps -a"