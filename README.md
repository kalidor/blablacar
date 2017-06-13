# Blablacar
[![Build Status](https://api.travis-ci.org/kalidor/blablacar.svg?branch=master)](https://travis-ci.org/kalidor/blablacar)

Since there is no public API for intreract with your account on Blablacar, I did something to do so.

**EDIT:** It appears something is finally coming out (see  https://dev.blablacar.com/), but just a few functionalities are supported yet.

Here are the functionalities it offers:
+ List planned trip with passengers (tel, note, age, etc.)
+ Respond to a public question
+ Enter trip validation code
+ Enter trip passenger opinion
+ Request money transfer
+ Check money transfer status
+ Get current user opinions
+ Duplicate passed or planned trip (Please use YYYY/MM/DD) (error are displayed but it works, still working on it)
+ Update number of seats for a trip (Please use YYYY/MM/DD)

The configuration file is a JSON format file. The cookie paramater is used to avoid a re-authentication.
Here is an example of conf.rc file. The full path is: ~/.blablacar/conf.rc (yes it's a hidden directory), but could be specified in command line:
```bash
user: toto@foo.com
pass: "My!AwesomeP4ssw0rd"
cookie: /tmp/blablacar.cookie
```

# Installation
```bash
$ gem build blablacar.gemspec
Successfully built RubyGem
Name: blablacar
Version: 0.1
File: blablacar-0.1.gem
$ gem install blablacar-0.1.gem
# maybe you have to use sudo to install the gem file
```

# Examples
List planned trip:
```bash
% blablacar.rb -l
Lyon -> Annecy (Vendredi 18 Dec à 17:50). Trip seen 56 times
  |  [COMPLETE]
  |  Hugo K (21 ans) 4.4★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Annecy
  |  Amelie R (20 ans) 4.1★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Chambery
  |  Christophe R (27 ans) 4.5★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Annecy
```

List my reservations:
```bash
% blablacar.rb -w
[+] Authentifié
[+] Vos réservations:
Aujourd'hui à 06:20 avec 'Violaine S' (XX XX XX XX XX ) [introuvable]
 | Annecy -> Lyon [confirmée] (1 place - 9,50 €)

Aujourd'hui à 18:20 avec 'Celine S' (XX XX XX XX XX ) [DVEBHA]
 | Lyon -> Annecy [Acceptée] (1 place - 11,00 €)

jeu. 05 janv. à 06:40 avec 'Laurent R' (XX XX XX XX XX ) [ZCOXYA]
 | Annecy -> Écully [Acceptée] (1 place - 11,00 €)

jeu. 05 janv. à 18:20 avec 'Celine S' (XX XX XX XX XX ) [HOYGYA]
 | Lyon -> Annecy [Acceptée] (1 place - 11,00 €)
```

Show notifications:
```bash
% ./blablacar.rb -N
[+] Authentifié
Notifications:
Apres votre voyage Annecy-Bron, renseignez le code passager de Christel C pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, renseignez le code passager de Rodolphe B pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, renseignez le code passager de Christophe R pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, laissez un avis a votre passager Frederic O
```

Register code to confirm we had a trip with "Christophe R":
```bash
% blablacar.rb --user "Christophe R" --code GIRSXK
[+] Authentifié
Apres votre voyage Bron-Annecy, renseignez le code passager de Christophe R pour recevoir €9 rapidement.
[+] Code ok pour Christophe R
```

Send an opinion about a passenger / driver:
```bash
% blablacar.rb -p --user "Christophe R" --avis "Sympa, ponctuel. Des discussions vraiment interessantes\!\! Je recommande" --note 5
[+] Authentifié
Apres votre voyage Bron-Annecy, laissez un avis a votre passager Christophe R
Avis envoye
```

Multiple option in one command line:
```
% blablacar.rb -lNMm
[+] Authentifié
No new messages  # -m
Notification:    # -N
Après votre voyage Lyon-Annecy, laissez un avis à votre passager Arthur D
Après votre voyage Lyon-Annecy, laissez un avis à votre passager Marie
Total already requested: 1 467 €  # -M
Available money: 69 €             # -M
Getting next planned trips:       # -l
No future planned trip(s)
```

Ask for transfert money:
```
% blablacar.rb -t
[+] Authentifié
Transfer successfully requested
```
Show payment status:
```bash
% blablacar.rb -s
[+] Authentifié
Transfer successfully requested
Money status (lastpage):
  INN H (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  TNT A (1 place - 6 €) - Lyon -> Chambéry [Virement en cours]
  SYT C (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  SYH K (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  OAI E (2 places - 18 €) - Bron -> Annecy [Verifications en cours]
  FDN R (1 place - 9 €) - Lyon -> Annecy [Virement effectué le 04/12/2015]
  UOK S (2 places - 6 €) - Lyon -> Chambéry [Virement effectué le 04/12/2015]
```

Update seat for a trip (set up 2 seats for this trip):
```
% blablacar.rb -T "2015/12/14" -S 2
[+] Authentifié
OK
```

Accept a trip pessenger request:
```
bin/blablacar --accept -u "Lucie D" -T "Demain à 18h"
```

Duplicate trip:
```
% blablacar.rb --duplicate "2015/12/12 à 6h" --trip "2015/12/14 à 6h"
[+] Authentifié
[+] Trip is being processed...
[+] Trip duplicated
```
