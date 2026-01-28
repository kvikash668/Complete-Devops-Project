# Complete-Devops-Project
# End-to-End DevSecOps Pipeline with GitOps on AWS EKS

An end-to-end **DevSecOps CI/CD pipeline** implementing **security, automation, and GitOps principles** to deploy a **three-tier MERN stack application (Socio-Echo)** on **AWS EKS**.  
The pipeline integrates **Jenkins, SonarQube, Trivy, Docker, and ArgoCD** to achieve secure, reliable, and automated cloud-native deployments.

---
## 🎥 Project Demo Video

Click the thumbnail below to watch the complete end-to-end demonstration of the DevSecOps pipeline:

#[![DevSecOps Pipeline Demo](https://img.youtube.com/vi/5dfXffclH4s/0.jpg)](https://youtu.be/5dfXffclH4s)

This demo covers:
- Jenkins CI/CD pipeline execution
- SonarQube static code analysis
- Owasp-dependency check 
- Trivy container vulnerability scanning
- Docker image build and push
- GitOps-based deployment using ArgoCD
- Application deployment on AWS EKS


## 📌 Project Overview

This project demonstrates a complete **DevSecOps lifecycle**, starting from source code commit to automated deployment on Kubernetes using **GitOps methodology**.  
Security is embedded at every stage of the pipeline through static code analysis and container vulnerability scanning.

**Key Highlights:**
- Automated CI/CD using Jenkins
- Integrated security scans 
- GitOps-based Kubernetes deployments using ArgoCD
- Stable and Canary deployment strategy
- Monitoring with grafana and prometheus

---

## 🏗️ High-Level Architecture

**Workflow Summary:**

1. Developer pushes code to GitHub  
2. Jenkins pipeline (running on AWS EC2) is triggered  
3. Jenkins performs:
   - SonarQube code quality analysis
   - Owasp-dependency check
   - Trivy vulnerability scanning  
   - Docker image build and push  
   - Kubernetes manifest updates (Stable & Canary)  
4. Updated YAML files are pushed back to GitHub  
5. ArgoCD detects changes and syncs them to AWS EKS  
6. Application is deployed as Pods, Services, and Deployments  

---

## 🔍 Detailed Design

### CI/CD Workflow

- Code commits trigger Jenkins via GitHub webhook  
- Jenkins executes the following stages:
  - Repository cloning  
  - SonarQube static code analysis
  - Owasp-dependency check
  - Trivy container vulnerability scanning  
  - Docker image build and push to registry  
  - Update Kubernetes deployment manifests with new image tags  
- Changes are committed back to GitHub  

### GitOps Deployment

- ArgoCD continuously monitors the GitHub repository  
- Any change in Kubernetes manifests automatically syncs to AWS EKS  
- Stable and Canary deployments are updated seamlessly  
- Services are updated accordingly for traffic routing  

---

## ⚙️ Implementation Details

### 4.1 Proposed Methodology

The pipeline integrates security and automation tools to achieve DevSecOps workflows:

- **Jenkins** manages CI/CD automation  
- **SonarQube** ensures code quality and maintainability
- **Owasp-dependency** checks CVE's in dependencies used
- **Trivy** scans Docker images for vulnerabilities  
- **Docker** packages the application  
- **ArgoCD** handles GitOps-based deployments to AWS EKS  
- **Prometheus and grafana** enables monitoring and observability  

---

### 4.2 Algorithm Used for Implementation

1. Start Jenkins pipeline  
2. Clone code from GitHub  
3. Analyze code using SonarQube
4. Owasp-dependency check
5. Scan Docker image vulnerabilities using Trivy  
6. Build and push Docker image  
7. Update stable and canary Kubernetes YAML files  
8. Push updated manifests to GitHub  
9. ArgoCD syncs the EKS cluster  
10. Deploy updated application versions  
11. Monitor application using Prometheus and Grafana 

---

## 🛠️ Tools & Technologies Used

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/1fce101b-da89-4ec1-bb7f-b5ba8ce91eb5" />


---

## 🧪 Testing & Validation

The following validations were performed:

- Successful Jenkins pipeline execution  
- Code quality verification via SonarQube  
- Vulnerability detection using Trivy  
- Automated GitOps deployments using ArgoCD  
- Application availability on AWS EKS  
- Monitoring logs and metrics via Prometheus and Grafana

---

## 📂 Application Used

This pipeline deploys an **open-source three-tier MERN stack application**:

- **Project Name:** Socio-Echo  
- **Architecture:**  
  - Frontend: React  
  - Backend: Node.js & Express  
  - Database: MongoDB
  - github url: https://github.com/kvikash668/SocialEcho.git

The application was containerized and deployed using Kubernetes on AWS EKS.

---

## 👥 Contributors

- **Vikash Kumar**

---


## 📄 License

This project is for educational and demonstration purposes.
