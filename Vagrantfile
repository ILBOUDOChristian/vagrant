# -*- mode: ruby -*-
# frozen_string_literal: true
# RÉSULTATS-BF jalon 1. GROUPE_RESEAU (1..8) calcule le sous-réseau.
# NOEUDS alimente les VM et config/noeuds.yml.

require "yaml"
require "fileutils"

env_path = File.join(__dir__, ".env")
if File.exist?(env_path)
  File.foreach(env_path).with_index(1) do |line, line_number|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")

    match = /\A([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*\z/.match(stripped)
    raise ".env invalide à la ligne #{line_number}." unless match

    key = match[1]
    value = match[2]
    if value.start_with?("\"", "'")
      quote = value[0]
      raise ".env invalide à la ligne #{line_number} : guillemets non appariés." unless value.end_with?(quote)

      value = value[1...-1]
    end
    ENV[key] = value unless ENV.key?(key) && !ENV[key].to_s.empty?
  end
end

def entier_env(nom, valeur, minimum, maximum = nil)
  unless /\A\d+\z/.match?(valeur.to_s)
    raise "#{nom} doit être un entier."
  end

  entier = valeur.to_i
  if entier < minimum || (maximum && entier > maximum)
    plage = maximum ? "#{minimum}..#{maximum}" : "supérieur ou égal à #{minimum}"
    raise "#{nom} doit être #{plage}."
  end

  entier
end

GROUPE_EQUIPE = entier_env("GROUPE_EQUIPE", ENV["GROUPE_EQUIPE"], 1)
GROUPE_RESEAU = entier_env("GROUPE_RESEAU", ENV["GROUPE_RESEAU"], 1, 8)
# Le sujet impose N >= 2 serveurs applicatifs sans état
NB_APP = entier_env("NB_APP", ENV["NB_APP"], 2, 10)
RESEAU = "192.168.#{55 + GROUPE_RESEAU}"
BOITE = ENV["BOITE_IMAGE"].to_s.strip
VERSION = ENV["BOITE_VERSION"].to_s.strip
PORT_HOTE = entier_env("PORT_HOTE", ENV["PORT_HOTE"], 1024, 65535)

if BOITE.empty? || VERSION.empty?
  raise "BOITE_IMAGE et BOITE_VERSION doivent être définis dans .env."
end

BDD_HOST_PRIMAIRE = ENV["BDD_HOST_PRIMAIRE"].to_s.strip
BDD_HOST_SECONDAIRE = ENV["BDD_HOST_SECONDAIRE"].to_s.strip
MEM_BDD = entier_env("MEM_BDD", ENV["MEM_BDD"], 256, 4096)
MEM_APP = entier_env("MEM_APP", ENV["MEM_APP"], 256, 4096)
MEM_LB = entier_env("MEM_LB", ENV["MEM_LB"], 256, 4096)

if BDD_HOST_PRIMAIRE.empty? || BDD_HOST_SECONDAIRE.empty?
  raise "BDD_HOST_PRIMAIRE et BDD_HOST_SECONDAIRE doivent être définis dans .env."
end

NOEUDS = []
NOEUDS << { nom: BDD_HOST_PRIMAIRE, ip: "#{RESEAU}.31", mem: MEM_BDD, role: "bdd" }
NOEUDS << { nom: BDD_HOST_SECONDAIRE, ip: "#{RESEAU}.32", mem: MEM_BDD, role: "replique" }
(1..NB_APP).each do |i|
  NOEUDS << { nom: "app#{i}", ip: "#{RESEAU}.#{20 + i}", mem: MEM_APP, role: "app" }
end
NOEUDS << { nom: "lb1", ip: "#{RESEAU}.11", mem: MEM_LB, role: "lb" }

ACTIVER_EXTENSION_E1 = ENV.fetch("ACTIVER_EXTENSION_E1", "false").to_s.strip.downcase == "true"
if ACTIVER_EXTENSION_E1
  NOEUDS << { nom: "lb2", ip: "#{RESEAU}.12", mem: MEM_LB, role: "lb" }
end

FileUtils.mkdir_p(File.join(__dir__, "config"))
inventaire = NOEUDS.map do |n|
  { "nom" => n[:nom], "ip" => n[:ip], "mem" => n[:mem], "role" => n[:role] }
end
noeuds_path = File.join(__dir__, "config", "noeuds.yml")
nouveau_yaml = inventaire.to_yaml
if !File.exist?(noeuds_path) || File.read(noeuds_path) != nouveau_yaml
  File.write(noeuds_path, nouveau_yaml)
end

["POSTGRES_USER", "POSTGRES_DB", "POSTGRES_PASSWORD"].each do |var|
  if ENV[var].to_s.strip.empty?
    raise "#{var} doit être obligatoirement défini dans le fichier .env."
  end
end

PROVISION_ENV = {
  "GROUPE_EQUIPE" => GROUPE_EQUIPE.to_s,
  "GROUPE_RESEAU" => GROUPE_RESEAU.to_s,
  "RESEAU" => RESEAU,
  "PORT_HOTE" => PORT_HOTE.to_s,
  "APP_HOST" => ENV["APP_HOST"].to_s.strip,
  "APP_PORT" => ENV["APP_PORT"].to_s.strip,
  "BDD_PORT" => ENV["BDD_PORT"].to_s.strip,
  "POSTGRES_USER" => ENV["POSTGRES_USER"].to_s.strip,
  "POSTGRES_DB" => ENV["POSTGRES_DB"].to_s.strip,
  "POSTGRES_PASSWORD" => ENV["POSTGRES_PASSWORD"].to_s.strip,
  "URL_API_BASE" => ENV.fetch("URL_API_BASE", "http://#{RESEAU}.10").to_s.strip
}

IP_HOTE = ENV["IP_HOTE"].to_s.strip
PORT_INVITE = entier_env("PORT_INVITE", ENV["PORT_INVITE"], 1, 65535)

if IP_HOTE.empty?
  raise "IP_HOTE doit être défini dans .env."
end

Vagrant.configure("2") do |config|
  config.vm.box = BOITE
  config.vm.box_version = VERSION
  config.vm.box_check_update = false

  NOEUDS.each do |n|
    config.vm.define n[:nom], primary: (n[:role] == "lb") do |m|
      m.vm.hostname = n[:nom]
      m.vm.network "private_network", ip: n[:ip]

      if n[:role] == "lb"
        m.vm.network "forwarded_port",
                     guest: PORT_INVITE,
                     host: PORT_HOTE,
                     host_ip: IP_HOTE
      end

      m.vm.provider "virtualbox" do |vb|
        vb.name = "resultats-bf-#{n[:nom]}"
        vb.memory = n[:mem]
        vb.cpus = 1
      end

      m.vm.provision "shell", path: "scripts/commun.sh", env: PROVISION_ENV
      m.vm.provision "shell", path: "scripts/#{n[:role]}.sh", env: PROVISION_ENV
    end
  end

  # Message de confirmation final avec le lien direct vers le portail
  config.trigger.after :up do |trigger|
    trigger.ruby do |env, machine|
      # N'affiche le récapitulatif qu'une seule fois à la toute fin
      if machine.nil? || machine.name.to_s == "lb1"
        puts "\n" + ("=" * 72)
        puts "  INFRASTRUCTURE RESULTATS-BF DEPLOYEE AVEC SUCCES !"
        puts "  Portail Web disponible sur : http://#{IP_HOTE}:#{PORT_HOTE}/"
        puts "  Sonde de sante active     : http://#{IP_HOTE}:#{PORT_HOTE}/sante"
        puts "  Repartition de charge     : http://#{IP_HOTE}:#{PORT_HOTE}/info"
        puts "  Recherche de resultat     : http://#{IP_HOTE}:#{PORT_HOTE}/resultat?matricule=BF-000006"
        puts ("=" * 72) + "\n\n"
      end
    end
  end
end
