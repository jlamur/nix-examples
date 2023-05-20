{ config, pkgs, ... }:
let
  realm = "KRB.TEST";
  nginxHostname = "test-kdc.internal";

  # Watch out, these are stored clear in the nix store.
  masterKey = "master_key";
  adminPassword = "admin_pw";
  alicePassword = "alice_pw";

  keytabPath = "/var/run/nginx.keytab";
in
{
  # Network configuration.
  networking.useDHCP = false;
  networking.firewall.allowedTCPPorts = [ 80 88 749 ];

  # Set a default password to debug
  users.users.root.password = "hunter2";

  # Enable a web server.
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 80;
    additionalModules = [ pkgs.nginxModules.spnego-http-auth ];
    virtualHosts."default" = {
      locations."/" = {
        extraConfig = ''
          auth_gss on;
          auth_gss_realm ${realm};
          auth_gss_keytab ${keytabPath};
          auth_gss_service_name HTTP/${nginxHostname};
          auth_gss_allow_basic_fallback on;
        '';
        root = pkgs.writeTextDir "index.html" ''
          Hello world! :-)
          This is NixOS speaking!
        '';
      };
      default = true;
    };
  };

  services.kerberos_server = {
    enable = true;
    realms = {
      ${realm} = {
        acl = [ { access = "all"; principal = "admin/admin"; } ];
      };
    };
  };

  krb5 = {
    enable = true;
    libdefaults.default_realm = realm;
    realms.${realm} = {
      admin_server = "localhost";
      kdc = "localhost";
    };
  };

  systemd.services.kdc-bootstrap = {
    enable = true;
    unitConfig = {
      Before = [ "kdc.service" "kadmind.service" ];
      ConditionPathExists = "!/var/lib/krb5kdc/principal";
    };
    serviceConfig = {
      ExecStart = [
        "${pkgs.coreutils}/bin/mkdir -p /var/lib/krb5kdc"
        "${pkgs.krb5}/bin/kdb5_util create -s -r ${realm} -P ${masterKey}"
        "${pkgs.krb5}/bin/kadmin.local add_principal -pw ${adminPassword} admin/admin"
        "${pkgs.krb5}/bin/kadmin.local add_principal -pw ${alicePassword} alice"
        "${pkgs.krb5}/bin/kadmin.local add_principal -randkey HTTP/${nginxHostname}"
      ];
      Type = "oneshot";
    };
    requiredBy = [ "kdc.service" "kadmind.service" ];
  };

  systemd.services.nginx-kdc-bootstrap = {
    enable = true;
    unitConfig = {
      Before = [ "nginx.service" ];
      After = [ "kdc-bootstrap.service" ];
      ConditionPathExists = "!${keytabPath}";
    };
    serviceConfig = {
      ExecStart = [
        "${pkgs.krb5}/bin/kadmin.local ktadd -k ${keytabPath} HTTP/${nginxHostname}"
        "${pkgs.coreutils}/bin/chown nginx:nginx ${keytabPath}"
      ];
      Type = "oneshot";
    };
    requiredBy = [ "nginx.service" ];
  };
}
