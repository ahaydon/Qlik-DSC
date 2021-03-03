project_root = File.dirname(__FILE__)
Vagrant.configure("2") do |c|
    c.vm.provision :shell do |shell|
        shell.path = File.join(project_root, "bootstrap.ps1")
    end
end
