Vagrant.require_version ">= 1.6.2"

Vagrant.configure(2) do |config|
    config.vm.define "docker", primary: true do |srv|
        srv.vm.box = "ubuntu/focal64"

        srv.vm.provider :virtualbox do |v, override|
            v.name = "Qlik-DSC-CI"
            v.linked_clone = true
            v.customize ["modifyvm", :id, "--memory", 2048]
            v.customize ["modifyvm", :id, "--cpus", 2]
            v.customize ["modifyvm", :id, "--vram", 64]
            v.customize ["modifyvm", :id, "--clipboard", "disabled"]
            v.customize ["modifyvm", :id, "--chipset", "ich9"]
            v.customize ["modifyvm", :id, "--uart1", "off"]
        end

        srv.vm.hostname = "qlik-dsc-docker"

        srv.vm.provision :shell, inline: <<-EOF
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo \
                "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get -y update
            sudo apt-get -y install docker-ce docker-ce-cli containerd.io

            sudo usermod -aG docker vagrant
            sudo usermod -aG docker ubuntu

            sudo systemctl enable docker.service
            sudo systemctl enable containerd.service

            curl -fsSL https://raw.githubusercontent.com/CircleCI-Public/circleci-cli/master/install.sh | sudo bash
            echo ". <(circleci completion bash)" >> ~/.bashrc
EOF

    end
end
