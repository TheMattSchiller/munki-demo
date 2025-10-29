#!/usr/bin/env python3
"""
AutoPkg Runner Script

Reads config.yaml and:
1. Configures AutoPkg plist with MUNKI_REPO
2. Adds all configured repositories
3. Runs each configured recipe
"""

import os
import sys
import subprocess
import yaml
import logging
import argparse
from pathlib import Path

try:
    import paramiko
except ImportError:
    paramiko = None

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class AutoPkgRunner:
    def __init__(self, config_path='config.yaml'):
        """Initialize the AutoPkg runner with config file."""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.script_dir = Path(__file__).parent
        
    def _load_config(self):
        """Load configuration from YAML file."""
        if not self.config_path.exists():
            logger.error(f"Config file not found: {self.config_path}")
            sys.exit(1)
            
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
            logger.info(f"Loaded configuration from {self.config_path}")
            return config
        except yaml.YAMLError as e:
            logger.error(f"Error parsing YAML config: {e}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            sys.exit(1)
    
    def _run_command(self, command, check=True, capture_output=False):
        """Run a shell command and return the result."""
        try:
            logger.debug(f"Running command: {' '.join(command)}")
            result = subprocess.run(
                command,
                check=check,
                capture_output=capture_output,
                text=True
            )
            # Always return the full result object when capture_output is True
            # This allows access to both stdout and stderr
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed: {' '.join(command)}")
            if e.stderr:
                logger.error(f"Error output: {e.stderr}")
            if check:
                raise
            return None
        except FileNotFoundError:
            logger.error(f"Command not found: {command[0]}")
            logger.error("Make sure AutoPkg is installed and in PATH")
            sys.exit(1)
    
    def configure_munki_repo(self):
        """Configure AutoPkg MUNKI_REPO preference."""
        repo_path = self.config.get('repo_path')
        if not repo_path:
            logger.warning("No repo_path specified in config, skipping MUNKI_REPO configuration")
            return
        
        # Resolve relative path from config file location
        if not os.path.isabs(repo_path):
            repo_path = os.path.join(self.script_dir, repo_path)
        repo_path = os.path.abspath(repo_path)
        
        if not os.path.exists(repo_path):
            logger.warning(f"MUNKI_REPO path does not exist: {repo_path}")
            logger.warning("Skipping MUNKI_REPO configuration")
            return
        
        logger.info(f"Configuring MUNKI_REPO: {repo_path}")
        try:
            # Use defaults command to set the preference
            self._run_command([
                'defaults', 'write', 'com.github.autopkg', 'MUNKI_REPO', repo_path
            ])
            logger.info("MUNKI_REPO configured successfully")
        except Exception as e:
            logger.error(f"Failed to configure MUNKI_REPO: {e}")
            raise
    
    def add_repositories(self):
        """Add all repositories from config."""
        repos = self.config.get('repos', [])
        if not repos:
            logger.warning("No repositories specified in config")
            return
        
        logger.info(f"Adding {len(repos)} repository(ies)...")
        for repo in repos:
            name = repo.get('name')
            url = repo.get('url')
            
            if not name or not url:
                logger.warning(f"Skipping invalid repo entry: {repo}")
                continue
            
            logger.info(f"Adding repository: {name} ({url})")
            try:
                # Try to add the repo
                # If it already exists, autopkg will return non-zero, but that's ok
                result = self._run_command(
                    ['autopkg', 'repo-add', name],
                    check=False,
                    capture_output=True
                )
                
                # Check if repo is already added
                if result and result.returncode != 0:
                    # Verify if it's already in the list
                    repo_list_result = self._run_command(
                        ['autopkg', 'repo-list'],
                        capture_output=True
                    )
                    repo_list_output = repo_list_result.stdout if repo_list_result else ""
                    if name in repo_list_output or url in repo_list_output:
                        logger.info(f"Repository '{name}' is already added")
                    else:
                        logger.warning(f"Failed to add repository '{name}', may already exist")
                else:
                    logger.info(f"Repository '{name}' added successfully")
                    if result and result.stdout:
                        logger.debug(result.stdout)
                    
            except Exception as e:
                logger.error(f"Error adding repository '{name}': {e}")
                # Continue with other repos even if one fails
    
    def configure_trust_info(self):
        """Configure AutoPkg to suppress trust info warnings."""
        logger.info("Configuring AutoPkg trust info preference...")
        try:
            # Set FAIL_RECIPES_WITHOUT_TRUST_INFO to false
            # When set to false, AutoPkg proceeds without failing, but may still show warnings
            # We'll also try setting it via environment variable as some versions check that first
            self._run_command([
                'defaults', 'write', 'com.github.autopkg', 
                'FAIL_RECIPES_WITHOUT_TRUST_INFO', '-bool', 'false'
            ])
            # Also set via environment - AutoPkg may check this
            os.environ['FAIL_RECIPES_WITHOUT_TRUST_INFO'] = 'false'
            logger.info("FAIL_RECIPES_WITHOUT_TRUST_INFO configured")
        except Exception as e:
            logger.warning(f"Failed to configure trust info preference: {e}")
            # Continue anyway - this is not critical
    
    def run_recipes(self):
        """Run all recipes from config."""
        recipes = self.config.get('recipes', [])
        if not recipes:
            logger.warning("No recipes specified in config")
            return
        
        logger.info(f"Running {len(recipes)} recipe(s)...")
        # Set environment variable for AutoPkg to suppress trust warnings
        env = os.environ.copy()
        env['FAIL_RECIPES_WITHOUT_TRUST_INFO'] = 'false'
        
        for recipe in recipes:
            if not recipe:
                continue
                
            logger.info(f"Running recipe: {recipe}")
            try:
                # Pass the environment with FAIL_RECIPES_WITHOUT_TRUST_INFO set
                result = subprocess.run(
                    ['autopkg', 'run', '-v', recipe],
                    check=False,
                    env=env
                )
                if result.returncode == 0:
                    logger.info(f"Recipe '{recipe}' completed successfully")
                else:
                    logger.error(f"Recipe '{recipe}' failed with exit code {result.returncode}")
                    # Continue with other recipes even if one fails
            except Exception as e:
                logger.error(f"Recipe '{recipe}' failed: {e}")
                # Continue with other recipes even if one fails
    
    def upload_repo(self):
        """Upload munki repo to SFTP server using config credentials."""
        if paramiko is None:
            logger.error("paramiko library is required for SFTP upload")
            logger.error("Install it with: pip install paramiko")
            sys.exit(1)
        
        # Get SFTP configuration
        sftp_host = self.config.get('sftp_host')
        sftp_port = self.config.get('sftp_port', 22)
        sftp_user = self.config.get('sftp_user')
        sftp_password = self.config.get('sftp_password')
        
        if not all([sftp_host, sftp_user, sftp_password]):
            logger.error("Missing SFTP configuration (sftp_host, sftp_user, sftp_password required)")
            sys.exit(1)
        
        # Get repo path from config
        repo_path = self.config.get('repo_path')
        if not repo_path:
            logger.error("No repo_path specified in config")
            sys.exit(1)
        
        # Resolve relative path from config file location
        if not os.path.isabs(repo_path):
            repo_path = os.path.join(self.script_dir, repo_path)
        repo_path = os.path.abspath(repo_path)
        
        if not os.path.exists(repo_path):
            logger.error(f"Repository path does not exist: {repo_path}")
            sys.exit(1)
        
        logger.info(f"Connecting to SFTP server: {sftp_user}@{sftp_host}:{sftp_port}")
        logger.info("Authenticating with username/password from config file")
        
        transport = None
        sftp = None
        try:
            # Use Transport directly for explicit password authentication
            transport = paramiko.Transport((sftp_host, sftp_port))
            
            # Start transport and authenticate with password
            transport.start_client()
            transport.auth_password(username=sftp_user, password=sftp_password)
            
            # Open SFTP session
            sftp = paramiko.SFTPClient.from_transport(transport)
            logger.info("SFTP connection established")
            
            # Upload directory recursively
            self._upload_directory(sftp, repo_path, '/')
            
            logger.info("Repository upload completed successfully")
            
        except paramiko.AuthenticationException:
            logger.error("SFTP authentication failed - check username/password in config")
            sys.exit(1)
        except paramiko.SSHException as e:
            logger.error(f"SFTP connection error: {e}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"SFTP upload failed: {e}")
            sys.exit(1)
        finally:
            # Always close connections
            if sftp:
                try:
                    sftp.close()
                except:
                    pass
            if transport:
                try:
                    transport.close()
                except:
                    pass
    
    def _upload_directory(self, sftp, local_dir, remote_dir):
        """Recursively upload a directory to SFTP server."""
        logger.info(f"Uploading {local_dir} -> {remote_dir}")
        
        # Ensure remote directory exists (create parent directories if needed)
        self._ensure_remote_directory(sftp, remote_dir)
        
        # Walk through local directory
        for item in os.listdir(local_dir):
            local_path = os.path.join(local_dir, item)
            remote_path = f"{remote_dir.rstrip('/')}/{item}"
            
            if os.path.isdir(local_path):
                # Recursively upload subdirectories
                self._upload_directory(sftp, local_path, remote_path)
            else:
                # Upload file
                logger.debug(f"Uploading file: {local_path} -> {remote_path}")
                sftp.put(local_path, remote_path)
                logger.debug(f"Uploaded: {item}")
    
    def _ensure_remote_directory(self, sftp, remote_dir):
        """Ensure remote directory exists, creating parent directories if needed."""
        try:
            sftp.stat(remote_dir)
        except FileNotFoundError:
            # Try to create the directory and all parent directories
            parts = remote_dir.rstrip('/').split('/')
            current_path = ''
            for part in parts:
                if not part:
                    continue  # Skip empty parts (from leading /)
                current_path = f"{current_path}/{part}" if current_path else f"/{part}"
                try:
                    sftp.stat(current_path)
                except FileNotFoundError:
                    try:
                        sftp.mkdir(current_path)
                        logger.debug(f"Created remote directory: {current_path}")
                    except Exception as e:
                        logger.debug(f"Directory may already exist or mkdir failed: {e}")
    
    def run(self):
        """Main execution method - runs all steps in order."""
        logger.info("Starting AutoPkg configuration and recipe execution...")
        
        try:
            # Step 1: Configure MUNKI_REPO
            self.configure_munki_repo()
            
            # Step 2: Configure trust info preference (suppress warnings)
            self.configure_trust_info()
            
            # Step 3: Add repositories
            self.add_repositories()
            
            # Step 4: Run recipes
            self.run_recipes()
            
            logger.info("AutoPkg runner completed successfully")
        except Exception as e:
            logger.error(f"AutoPkg runner failed: {e}")
            sys.exit(1)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='AutoPkg Runner - Configure AutoPkg and run recipes',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        '--upload',
        action='store_true',
        help='Upload munki repository to SFTP server without running recipes'
    )
    parser.add_argument(
        '--config',
        type=str,
        default=None,
        help='Path to config.yaml file (default: config.yaml in script directory)'
    )
    
    args = parser.parse_args()
    
    # Get the directory where the script is located
    script_dir = Path(__file__).parent
    
    if args.config:
        config_path = Path(args.config)
    else:
        config_path = script_dir / 'config.yaml'
    
    runner = AutoPkgRunner(config_path=str(config_path))
    
    if args.upload:
        runner.upload_repo()
    else:
        runner.run()


if __name__ == '__main__':
    main()

