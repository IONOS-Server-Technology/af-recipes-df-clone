#!/usr/bin/env bash
# install.sh — Install Jenkins via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Create the persistent data directory that Compose mounts as JENKINS_HOME.
mkdir -p /opt/jenkins/data/init.groovy.d

# Write the Groovy init script that creates the admin user on first boot.
# The script reads JENKINS_ADMIN_PASSWORD from the container environment (passed via
# Compose), so the bcrypt hash never needs to be substituted into the file itself.
# The realm check makes it idempotent: once Jenkins saves its config.xml with a
# HudsonPrivateSecurityRealm, subsequent restarts skip this block entirely.
cat > /opt/jenkins/data/init.groovy.d/01-create-admin.groovy << 'GROOVY'
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstanceOrNull()
if (instance == null) return

if (instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm) {
    println "Security realm already configured; skipping admin init."
    return
}

def adminPassword = System.getenv("JENKINS_ADMIN_PASSWORD")
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccountWithHashedPassword('admin', adminPassword)
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
println "Admin user 'admin' created."
GROOVY
