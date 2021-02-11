/* 
ATTENTION : 
 - remplacer la châine de caractère "dba" par le nom de votre utilisateur de postgresql, qui crée la base de données
 - remplacer la chaîne de caratctères "db_name" par le nom de la base postgis préalablement créée avant d'exécuter
 - remplacer le mot best_password par le mot de passe défini
 - Adaptez le script à votre projection carto en remplaçant la chaine "2154" par le code EPSG de votre projection.
 - Répercutez cette projections dans la configuration de l'application web
exemple : CREATE DATABASE sicen WITH TEMPLATE=template_postgis;
Remarque : connectez-vous à la base avant de lancer ce script
*/

/* Rôles et groupes de connexion */

CREATE ROLE db_name_cnx;
ALTER ROLE db_name_cnx WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN encrypted PASSWORD 'best_password';
CREATE ROLE db_name_amateur;
ALTER ROLE db_name_amateur WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN encrypted PASSWORD 'best_password';
CREATE ROLE db_name_expert;
ALTER ROLE db_name_expert WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN encrypted PASSWORD 'best_password';
CREATE ROLE db_name_admin;
ALTER ROLE db_name_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN encrypted PASSWORD 'best_password';

CREATE ROLE db_name_gr_observ;
ALTER ROLE db_name_gr_observ WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN;
CREATE ROLE db_name_gr_consult;
ALTER ROLE db_name_gr_consult WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN ;
CREATE ROLE db_name_gr_amateur;
ALTER ROLE db_name_gr_amateur WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN ;
CREATE ROLE db_name_gr_expert;
ALTER ROLE db_name_gr_expert WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN ;
CREATE ROLE db_name_gr_admin;
ALTER ROLE db_name_gr_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN;

GRANT db_name_gr_observ TO db_name_gr_consult;
GRANT db_name_gr_consult TO db_name_gr_amateur;
GRANT db_name_gr_amateur TO db_name_gr_expert;
GRANT db_name_gr_expert TO db_name_gr_admin;

GRANT db_name_gr_amateur TO db_name_amateur;
GRANT db_name_gr_admin TO db_name_admin;
GRANT db_name_gr_expert TO db_name_expert;

/* Droits d'accès principaux */

GRANT CONNECT ON DATABASE sicen TO db_name_gr_consult;
GRANT TEMPORARY ON DATABASE sicen TO db_name_gr_amateur;
GRANT CONNECT, TEMPORARY ON DATABASE sicen TO db_name_cnx;

GRANT SELECT ON TABLE spatial_ref_sys TO db_name_gr_consult;

/* 	
	PostgreSQL database dump 
	Dumped from database version 9.5.1
	Dumped by pg_dump version 9.5.1
	Started on 2016-04-20 09:46:28 UTC
*/

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

/* Pour les versions 9.5 et superieures de PostgreSQL
SET row_security = off;
*/

/* AJOUT des extensions qui pourraient manquer */

CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA public;
CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA public;

/* Création des schémas */

CREATE SCHEMA ign_bd_topo;
COMMENT ON SCHEMA ign_bd_topo IS 'Ce schéma contient initialement les tables de la BD TOPO.
Pour pouvoir utiliser l''application, il faut intégrer les données communales, avec composante spatiale à la table "commune".';

CREATE SCHEMA inpn;
COMMENT ON SCHEMA inpn IS 'Ce schéma contient les référentiels mis à disposition part l''INPN.
Ils ont été intégrés selon la méthde décrite ici : http://sig.cenlr.org/integration_donnees/externes/inpn .';

CREATE SCHEMA md;
COMMENT ON SCHEMA md IS 'Schéma permettant la gestion des métadonnées : personnes, structures, protocoles, études, sites lots de donnees.';

CREATE SCHEMA outils;

CREATE SCHEMA saisie;
COMMENT ON SCHEMA saisie IS 'Schéma de saisie des données : observations occasionelles naturalistes.';

CREATE SCHEMA stats;

SET search_path = md, public, pg_catalog;

CREATE TYPE enum_role AS ENUM (
    'observ',
    'consult',
    'amateur',
    'expert',
    'admin'
);

CREATE TYPE enum_specialite AS ENUM (
    'faune',
    'flore',
    'habitat',
    'fonge'
);

CREATE TYPE enum_titre AS ENUM (
    'Mme',
    'Melle',
    'M.'
);

SET search_path = saisie, public, pg_catalog;

CREATE TYPE enum_age AS ENUM (
    'Oeuf/ponte',
    'Juvénile',
    'Adulte',
    'Indéterminé'
);

CREATE TYPE enum_determination AS ENUM (
    'Vu',
    'Entendu',
    'Indice de présence',
    'Cadavre',
    'Capture'
);

CREATE TYPE enum_etat_de_conservation AS ENUM (
    'Bon',
    'Moyen',
    'Mauvais'
);

CREATE TYPE enum_phenologie AS ENUM (
    'Plantule',
    'Juvénille',
    'Adulte'
);

CREATE TYPE enum_precision AS ENUM (
    'GPS',
    '0 à 10m',
    '10 à 100m',
    '100 à 500m',
    'lieu-dit',
    'commune'
);

CREATE TYPE enum_qualification AS ENUM (
    'archive',
    'sensible'
);

CREATE TYPE enum_sexe AS ENUM (
    'Mâle',
    'Femelle',
    'Indéterminé'
);

CREATE TYPE enum_stade_phenologique AS ENUM (
    ''
);

CREATE TYPE enum_stade_reproductif AS ENUM (
    'Multiplication végétative',
    'Reproduction sexuée'
);

CREATE TYPE enum_statut_validation AS ENUM (
    'validée',
    'à valider',
    'non valide'
);

CREATE TYPE enum_type_effectif AS ENUM (
    ''
);

CREATE TYPE enum_unite AS ENUM (
    'Simple',
    'Mosaïque spatiale',
    'Mosaïque temporelle',
    'Mosaïque mixte'
);

SET search_path = md, public, pg_catalog;

CREATE FUNCTION creation_modification_observateur() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
DECLARE
	var_ancien_code_observateur character varying;
	var_ancien_login character varying;
	var_password character varying;
	var_ancien_role md.enum_role;
	var_nouveau_role md.enum_role;
	myrec RECORD;
 
BEGIN
	-- étape d''initialisation : suppression systématique de la vue sauf dans le cas de l''ajout
	IF (TG_OP <> 'INSERT') THEN
		EXECUTE 
			$req$
				DROP VIEW IF EXISTS saisie.saisie_observation_$req$||(OLD.id_personne)::text||$req$;
			$req$;
	END IF;
	-- si une nouvelle vue à créer ou à MàJ
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		-- si la création ou la MàJ de la vue concerne un compte numérisateur (rôle amateur, expert ou administrateur)
		IF ((NEW.role='amateur') OR (NEW.role='expert') OR (NEW.role='admin')) THEN
			EXECUTE 
			$req$
				CREATE OR REPLACE VIEW saisie.saisie_observation_$req$||(NEW.id_personne)::text||$req$ AS
				SELECT * FROM saisie.saisie_observation WHERE saisie_observation.numerisateur = $req$||NEW.id_personne||$req$;
				GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE saisie.saisie_observation_$req$||(NEW.id_personne)::text||$req$ TO db_name_gr_amateur;				
			$req$;
		RAISE INFO 'vue créée pour %', (NEW.id_personne)::text;
 
		RAISE INFO 'Création des règles d''accès à ces vues pour =%', NEW.email;		
		EXECUTE 
			$req$
				-- règle lors de l'ajout de données à la vue : INSERT
				CREATE OR REPLACE RULE insert_saisie_observation_$req$||(NEW.id_personne)::text||$req$ AS ON INSERT TO saisie.saisie_observation_$req$||(NEW.id_personne)::text||$req$
				DO INSTEAD
				INSERT INTO saisie.saisie_observation(phylum, classe, ordre, famille, nom_valide, heure_obs, date_obs, date_debut_obs, date_fin_obs, date_textuelle, regne, nom_vern, nom_complet, cd_nom, effectif_min, effectif_max, type_effectif, phenologie, id_waypoint, longitude, latitude, elevation, localisation, observateur, numerisateur, validateur, structure, remarque_obs, geometrie, code_insee, id_lieu_dit, determination, statut_validation, decision_validation, id_etude, id_protocole, effectif_textuel, diffusable, "precision", effectif, url_photo, commentaire_photo, qualification)
				VALUES (NEW.phylum, NEW.classe, NEW.ordre, NEW.famille, NEW.nom_valide, NEW.heure_obs, NEW.date_obs, NEW.date_debut_obs, NEW.date_fin_obs, NEW.date_textuelle, NEW.regne, NEW.nom_vern, NEW.nom_complet, NEW.cd_nom, NEW.effectif_min, NEW.effectif_max, NEW.type_effectif, NEW.phenologie, NEW.id_waypoint, NEW.longitude, NEW.latitude, NEW.elevation, NEW.localisation, NEW.observateur, NEW.numerisateur, NEW.validateur, NEW.structure, NEW.remarque_obs, NEW.geometrie, NEW.code_insee, NEW.id_lieu_dit, NEW.determination, NEW.statut_validation, NEW.decision_validation, NEW.id_etude, NEW.id_protocole, NEW.effectif_textuel, NEW.diffusable, NEW."precision", NEW.effectif, NEW.url_photo, NEW.commentaire_photo, NEW.qualification);
 
				-- règle lors de la mise à jour de données de la vue : UPDATE
				CREATE OR REPLACE RULE update_saisie_observation_$req$||(NEW.id_personne)::text||$req$ AS ON UPDATE TO saisie.saisie_observation_$req$||(NEW.id_personne)::text||$req$
				DO INSTEAD
				UPDATE saisie.saisie_observation
				SET phylum = NEW.phylum, classe = NEW.classe, ordre = NEW.ordre, famille = NEW.famille, nom_valide = NEW.nom_valide, heure_obs = NEW.heure_obs, date_obs = NEW.date_obs, date_debut_obs = NEW.date_debut_obs, date_fin_obs = NEW.date_fin_obs, date_textuelle = NEW.date_textuelle, regne = NEW.regne, nom_vern = NEW.nom_vern, nom_complet = NEW.nom_complet, cd_nom = NEW.cd_nom, effectif_min = NEW.effectif_min, effectif_max = NEW.effectif_max, type_effectif = NEW.type_effectif, phenologie = NEW.phenologie, id_waypoint = NEW.id_waypoint, longitude = NEW.longitude, latitude = NEW.latitude, elevation = NEW.elevation, localisation = NEW.localisation, observateur = NEW.observateur, numerisateur = NEW.numerisateur, validateur = NEW.validateur, structure = NEW.structure, remarque_obs = NEW.remarque_obs, geometrie = NEW.geometrie, code_insee = NEW.code_insee, id_lieu_dit = NEW.id_lieu_dit, determination = NEW.determination, statut_validation = NEW.statut_validation, decision_validation = NEW.decision_validation, id_etude = NEW.id_etude, id_protocole = NEW.id_protocole, effectif_textuel = NEW.effectif_textuel, diffusable = NEW.diffusable, "precision" = NEW."precision", effectif = NEW.effectif, url_photo = NEW.url_photo, commentaire_photo = NEW.commentaire_photo,
				qualification = NEW.qualification
				WHERE id_obs = OLD.id_obs;
 
				-- règle lors de la suppression d'une données de la vue : DELETE
				CREATE RULE delete_saisie_observation_$req$||(NEW.id_personne)::text||$req$ AS ON DELETE TO saisie.saisie_observation_$req$||(NEW.id_personne)::text||$req$
				DO INSTEAD
				DELETE FROM saisie.saisie_observation
				WHERE id_obs = OLD.id_obs;
			$req$;

		END IF;
	END IF;
	RETURN NULL;
END;
$_$;

CREATE FUNCTION liste_nom_auteur(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
  DECLARE
    var_liste_code_personne ALIAS for $1;
  BEGIN
        RETURN string_agg(nom || ' ' || prenom,' & ') FROM (SELECT unnest(string_to_array( var_liste_code_personne, '&'))::integer as id_personne) t
        JOIN md.personne USING(id_personne);
    
  END;
$_$;

CREATE FUNCTION liste_nom_structure(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
    var_liste_code_structure ALIAS for $1;
BEGIN
  RETURN string_agg(nom_structure,' & ') FROM (SELECT unnest(string_to_array( var_liste_code_structure, '&'))::integer as id_structure) t
  JOIN md.structure USING(id_structure);
END;
$_$;

SET search_path = outils, public, pg_catalog;

CREATE FUNCTION enum_add(enum_name character varying, enum_elem character varying, enum_schema character varying DEFAULT 'public'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    schemaoid       integer;
BEGIN
    SELECT oid INTO schemaoid FROM pg_namespace WHERE nspname = enum_schema;
    IF NOT FOUND THEN
    RAISE EXCEPTION 'Could not find schema ''%''', enum_schema;
    END IF;
    INSERT INTO pg_enum(enumtypid, enumlabel) VALUES(
        (SELECT oid FROM pg_type WHERE typtype='e' AND typname=enum_name AND typnamespace = schemaoid),
        enum_elem
    );
END;
$$;

CREATE FUNCTION enum_del(enum_name character varying, enum_elem character varying, enum_schema character varying DEFAULT 'public'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    type_oid INTEGER;
    rec RECORD;
    sql VARCHAR;
    ret INTEGER;
    schemaoid INTEGER;
BEGIN
    SELECT oid INTO schemaoid FROM pg_namespace WHERE nspname = enum_schema;
    IF NOT FOUND THEN
    RAISE EXCEPTION 'Could not find schema ''%''', enum_schema;
    END IF;
    SELECT pg_type.oid
    FROM pg_type
    WHERE typtype = 'e' AND typname = enum_name AND typnamespace = schemaoid
    INTO type_oid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot find a enum: %', enum_name;
    END IF;
    -- Check column DEFAULT value references.
    SELECT *
    FROM
        pg_attrdef
        JOIN pg_attribute ON attnum = adnum AND atttypid = type_oid
        JOIN pg_class ON pg_class.oid = attrelid
        JOIN pg_namespace ON pg_namespace.oid = relnamespace
    WHERE
        adsrc = quote_literal(enum_elem) || '::' || quote_ident(enum_name)
    LIMIT 1
    INTO rec;
    IF FOUND THEN
        RAISE EXCEPTION
            'Cannot delete the ENUM element %.%: column %.%.% has DEFAULT value of ''%''',
            quote_ident(enum_name), quote_ident(enum_elem),
            quote_ident(rec.nspname), quote_ident(rec.relname),
            rec.attname, quote_ident(enum_elem);
    END IF;
    -- Check data references.
    FOR rec IN
        SELECT *
        FROM
            pg_attribute
            JOIN pg_class ON pg_class.oid = attrelid
            JOIN pg_namespace ON pg_namespace.oid = relnamespace
        WHERE
            atttypid = type_oid
            AND relkind = 'r'
    LOOP
        sql :=
            'SELECT 1 FROM ONLY '
            || quote_ident(rec.nspname) || '.'
            || quote_ident(rec.relname) || ' '
            || ' WHERE '
            || quote_ident(rec.attname) || ' = '
            || quote_literal(enum_elem)
            || ' LIMIT 1';
        EXECUTE sql INTO ret;
        IF ret IS NOT NULL THEN
            RAISE EXCEPTION
                'Cannot delete the ENUM element %.%: column %.%.% contains references',
                quote_ident(enum_name), quote_ident(enum_elem),
                quote_ident(rec.nspname), quote_ident(rec.relname),
                rec.attname;
        END IF;
    END LOOP;
    -- OK. We may delete.
    DELETE FROM pg_enum WHERE enumtypid = type_oid AND enumlabel = enum_elem;
END;
$$;

CREATE FUNCTION get_user() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
declare
ergebnis text;
    BEGIN
        perform relname from pg_class
            where relname = 'icke_tmp'
              and case when has_schema_privilege(relnamespace, 'USAGE')
                    then pg_table_is_visible(oid) else false end;
  if not found then
    return 'inconnu';
  else
    select id_user from icke_tmp into ergebnis;
  end if;
  if not found then
    ergebnis:='inconnu';
  end if;
  RETURN ergebnis;
  END;
 $$;

CREATE FUNCTION set_user(myid_user text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    BEGIN
        perform relname from pg_class
            where relname = 'icke_tmp'
              and case when has_schema_privilege(relnamespace, 'USAGE')
                    then pg_table_is_visible(oid) else false end;
        if not found then
            create temporary table icke_tmp (
                id_user text
            );
        else
           delete from icke_tmp;
        end if;

        insert into icke_tmp values (myid_user);
  RETURN 0;
  END;
 $$;

SET search_path = saisie, public, pg_catalog;

CREATE FUNCTION alimente_suivi_saisie_observation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ declare
user_login text; BEGIN 
user_login = outils.get_user();
IF (TG_OP = 'DELETE') THEN INSERT INTO saisie.suivi_saisie_observation SELECT 'DELETE', now(), user_login, OLD.*; RETURN OLD; ELSIF (TG_OP = 'UPDATE') THEN INSERT INTO saisie.suivi_saisie_observation SELECT 'UPDATE', now(), user_login, NEW.*; RETURN NEW; ELSIF (TG_OP = 'INSERT') THEN INSERT INTO saisie.suivi_saisie_observation SELECT 'INSERT', now(), user_login, NEW.*; RETURN NEW; END IF; RETURN NULL; END; $$;

SET search_path = stats, public, pg_catalog;

CREATE FUNCTION cpt_nom_valide_suppl(text, integer, integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
var_regne ALIAS for $1;
    var_num_mois ALIAS for $2;
    var_annee ALIAS for $3;    
BEGIN
RETURN count(*) FROM (
select * from
stats.cpt_nom_valide_annee_mois
where regne= var_regne and annee = var_annee
and num_mois = var_num_mois
and nom_valide not in 

(select nom_valide from
stats.cpt_nom_valide_annee_mois
where regne= var_regne and annee <= var_annee
and num_mois < var_num_mois))t
group by mois;


END;
$_$;

SET search_path = ign_bd_topo, public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

CREATE TABLE commune (
    nom text,
    code_insee text NOT NULL,
    depart text,
    geometrie public.geometry(MultiPolygon,2154),
    dep character varying(3)
);

CREATE TABLE lieu_dit (
    id text NOT NULL,
    nom text,
    geometrie public.geometry(Point,2154)
);

SET search_path = inpn, public, pg_catalog;

CREATE TABLE taxref (
    regne text NOT NULL,
    phylum text,
    classe text,
    ordre text,
    famille text,
    cd_nom text NOT NULL,
    cd_ref text,
    nom_complet text,
    nom_valide text,
    nom_vern text,
    lb_nom text
);

COMMENT ON TABLE taxref IS 'Table issue du site de l''INPN.
Les genres ont été créés. Attention lors des mises à jour de référentiel.
Attention aussi aux espaces en début de chaine.
';

COMMENT ON COLUMN taxref.regne IS 'nom scientifique du règne du taxon';

COMMENT ON COLUMN taxref.cd_nom IS 'identifiant unique';

COMMENT ON COLUMN taxref.cd_ref IS 'renvoi au cd_nom du taxon de référence';

COMMENT ON COLUMN taxref.nom_complet IS 'nom scientifique complet du taxon (généralement lb_nom + lb_auteur)';

COMMENT ON COLUMN taxref.nom_vern IS 'nom vernaculaire du taxon en français';

CREATE TABLE typo_corine_biotopes (
    cd_cb text NOT NULL,
    lb_cb97_fr text
);

COMMENT ON TABLE typo_corine_biotopes IS 'Table : TYPO_CORINE_BIOTOPES
Nom du jeu de données : Typologie CORINE Biotopes
Date de création de la table : 09/07/2009
Date de dernière mise à jour de la table : 12/02/2010
Date de dernière mise à jour de la métadonnée : 08/04/2010
Auteur de la typologie : Pierre DEVILLERS, Jean DEVILLERS-TERSCHUREN et Jean-Paul LEDANT (Institut Royal des Sciences Naturelles, Bruxelles) pour la version originale de 1991. Myriam BISSARDON et Lucas GUIBAL (École nationale du génie rural, des eaux et des forêts, Nancy / ENGREF) pour la traduction française de 1997.
Auteur de la table : Vincent GAUDILLAT (Service du patrimoine naturel - Muséum national d''histoire naturelle / SPN-MNHN)
Territoire concerné : Europe de l''Ouest (Europe des 12 de l''époque : Allemagne, Belgique, Danemark, Espagne, France, Grande-Bretagne, Grèce, Irlande, Italie, Luxembourg, Pays-Bas, Portugal)
Organisme responsable : Commission européenne
Langue des données : UK, FR
Présentation / Contexte : La typologie CORINE Biotopes est un système hiérarchisé de classification des habitats européens élaboré dans le cadre du programme CORINE (Coordination of Information on the Environment). L''objectif était d''identifier et de décrire les biotopes d''importance majeure pour la conservation de la nature au sein de la Communauté européenne. Cette typologie parue en 1991 (Devillers et al.) comporte 2584 codes répartis en 7 grandes familles de milieux (1. Coastal and halophytic communities, 2. Non-marine waters, 3. Scrub and grassland, 4. Forests, 5. Bogs and marshes, 6. Inland rocks, screes and sands, 8. Agricultural land and artificial landscapes). Les habitats naturels et semi-naturels sont plus ou moins détaillés selon les cas avec une précision accrue pour certains types de végétations considérés comme ayant un fort intérêt patrimonial en Europe, les autres habitats sont traités plus sommairement. La typologie s''appuie largement sur la classification phytosociologique - avec laquelle elle propose des correspondances indicatives -, mais intègre également d''autres paramètres comme la dominance physionomique d''une espèce ou une localisation géographique donnée. Les codes à un chiffre correspondent aux grandes familles de milieux citées précédemment, on ajoute ensuite un autre chiffre puis une décimale et jusqu''à 6 chiffres après la décimale pour décrire des types de végétation de plus en plus précis. Cette typologie n''ayant fait l''objet d''aucune édition française, une traduction non officielle en français d''une partie de la typologie a été réalisée par l''ENGREF en 1997 (Bissardon et Guibal). Elle suit le texte original sans ajout de texte (mis à part 2 nouveaux codes par rapport à la version de 1991) mais seuls ont été repris les codes qui selon les auteurs concernaient la France. Il est à noter que les champs correspondants n''ont pas toujours été traduits dans leur intégralité. Cette version comporte 1478 codes (dont les 2 nouveaux codes précédemment évoqués). 
Description du travail : Mise en table de la typologie CORINE Biotopes avec mise en parallèle de la version originale de 1991 avec la version en français de 1997. Quelques petites corrections (essentiellement orthographiques ou typographiques) ont été apportées à l''occasion de la mise en table des textes. La création d''un champ "France" permet de filtrer les codes présents dans notre pays, il s''agit des codes de la version en français de 1997 auxquels quelques codes supplémentaires qui n''avaient pas été retenus dans celle-ci ont été ajoutés. Les intitulés et descriptifs de ces derniers ont été traduits dans leur intégralité (sauf précision contraire, ces traductions ont été effectuées par le SPN). Exceptionnellement, quelques codes cités dans la version en français ont été retirés car considérés comme absents en France.
Origine du jeu de données : Version originale en anglais (Devillers et al., 1991) : fichier Word envoyé par Dorian MOSS le 9/11/2007 ("CORINE HABITATS 1991.rtf"). Ce fichier comporte de légères différences avec la version éditée papier ; il s''agit généralement de différences typographiques, ponctuellement du remplacement d''un mot par un autre.  - Version en français (Bissardon et Guibal, 1997) : fichier Word envoyé par Jean-Claude RAMEAU (ENGREF) ("corin97.doc") correspondant au texte de la version éditée papier.
Références bibliographiques : DEVILLERS P., DEVILLERS-TERSCHUREN J., LEDANT J.-P. & coll., 1991. CORINE biotopes manual. Habitats of the European Community. Data specifications - Part 2. EUR 12587/3 EN. European Commission, Luxembourg, 300 p. [ISBN 92-826-3211-3] BISSARDON M. et GUIBAL L., 1997. Corine biotopes. Version originale. Types d''habitats français. ENGREF, Nancy, 217 p.
Mots clés : Typologie, habitats, Corine Biotopes, classification européenne.
Référencement à utiliser : DEVILLERS P., DEVILLERS-TERSCHUREN J., LEDANT J.-P. & coll., 1991. CORINE biotopes manual. Habitats of the European Community. Data specifications - Part 2. EUR 12587/3 EN. European Commission, Luxembourg, 300 p. Traduction pour les types d''habitats présents en France : BISSARDON M. et GUIBAL L., 1997. Corine biotopes. Version originale. Types d''habitats français. ENGREF, Nancy, 217 p. Mise en table : SPN-MNHN / INPN, février 2010.';

COMMENT ON COLUMN typo_corine_biotopes.cd_cb IS 'Code CORINE Biotopes, à 1 ou 2 chiffres suivis au maximum de 6 décimales. Dans le fichier Word de la version de 1991, le code 22.5 de la version papier est absent et on remarque le codage en 41.F3 de l habitat 41.F13 de la version papier (qui lui ne figure pas dans le fichier). Ces deux éléments ont été corrigés dans la présente table de manière à respecter la version papier, soit ajout du 22.5 et correction du 41.F3 en 41.F13. 2 codes apparaissant dans la version de 1997 n existent pas dans la version originale anglaise : 15.811 (Steppes à Lavande de mer ibériques) et 15.8114 (Steppes à Lavande de mer catalano-provençales). Ils ont néanmoins été ajoutés à la table générale, mais sans intitulé ou descriptif en anglais. Au chapitre 86 de la version de 1997 (papier et fichier original) les codes 86.411 à 86.6 ont été notés par erreur 84.411 à 84.6 ; ces codes ont été corrigés dans la présente base.;';

COMMENT ON COLUMN typo_corine_biotopes.lb_cb97_fr IS 'Intitulé de l''habitat selon la version en français de 1997 ou traduction nouvelle dans le cas de codes non retenus dans cette version mais présents en France.';

SET search_path = md, public, pg_catalog;

CREATE SEQUENCE etude_id_etude_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE etude (
    id_etude integer DEFAULT nextval('etude_id_etude_seq'::regclass) NOT NULL,
    nom_etude text,
    cahier_des_charges text,
    date_debut date,
    date_fin date,
    description text,
    lien_rapport_final text
);

COMMENT ON TABLE etude IS 'Cette table est nécessaire pour associer les données produites ou stockées dans la bdd aux études qui les ont mobilisé ou qui ont nécessité leur production. C''est un élément important de description de la donnée.';

CREATE TABLE personne (
    id_personne integer NOT NULL,
    remarque text,
    fax text,
    portable text,
    tel_pro text,
    tel_perso text,
    pays text,
    ville text,
    code_postal text,
    adresse_1 text,
    prenom text NOT NULL,
    nom text NOT NULL,
    email text,
    role enum_role,
    specialite enum_specialite,
    mot_de_passe text DEFAULT 0 NOT NULL,
    createur integer,
    titre enum_titre,
    date_maj date,
    id_structure integer
);

COMMENT ON TABLE personne IS 'Contient les informations relatives aux personnes ayant par exemple fourni des données au CEN LR ou ayant produit des données dans le cadre d''activité salariée ou de stage.';

COMMENT ON COLUMN personne.id_structure IS 'Structure unique d''appartenance de la personne à ne pas confondre avec la (ou les) structure(s) de production de la donnée en lien avec la saisie d''observations en cours';

CREATE SEQUENCE personne_id_personne_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE personne_id_personne_seq OWNED BY personne.id_personne;

CREATE TABLE protocole (
    id_protocole integer NOT NULL,
    libelle text,
    resume text
);

COMMENT ON TABLE protocole IS 'Liste les protocoles utilisés pour la récolte des donéees stockées dans le système d''information.';

CREATE SEQUENCE protocole_id_protocole_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE protocole_id_protocole_seq OWNED BY protocole.id_protocole;

CREATE TABLE structure (
    id_structure integer NOT NULL,
    nom_structure text,
    detail_nom_structure text,
    statut text,
    adresse_1 text,
    code_postal text,
    ville text,
    pays text,
    tel text,
    fax text,
    courriel_1 text,
    courriel_2 text,
    site_web text,
    remarque text,
    createur integer,
    diffusable boolean DEFAULT true,
    date_maj date
);

COMMENT ON TABLE structure IS 'Stocke les informations sur les structures partenaires du CEN, ou ayant produit des informations stockée ou ayant commandé des études...';

CREATE SEQUENCE structure_id_structure_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE structure_id_structure_seq OWNED BY structure.id_structure;

SET search_path = saisie, public, pg_catalog;

CREATE TABLE saisie_observation (
    id_obs integer NOT NULL,
    date_obs date,
    date_debut_obs date,
    date_fin_obs date,
    date_textuelle text,
    regne text,
    nom_vern text,
    nom_complet text,
    cd_nom text,
    effectif_textuel text,
    effectif_min bigint,
    effectif_max bigint,
    type_effectif text,
    phenologie text,
    id_waypoint text,
    longitude double precision,
    latitude double precision,
    localisation text,
    observateur text,
    numerisateur integer,
    validateur integer,
    structure text,
    remarque_obs text,
    code_insee text,
    id_lieu_dit text,
    diffusable boolean DEFAULT true,
    "precision" enum_precision,
    statut_validation enum_statut_validation,
    id_etude integer,
    id_protocole integer,
    effectif bigint,
    url_photo text,
    commentaire_photo text,
    decision_validation text,
    heure_obs time without time zone,
    determination enum_determination,
    elevation bigint,
    geometrie public.geometry(Geometry,2154),
    phylum text,
    classe text,
    ordre text,
    famille text,
    nom_valide text,
    qualification enum_qualification[]
);

COMMENT ON TABLE saisie_observation IS 'Table intermédaire entre les données extérieures au SI et les tables de la base de données.
Les données contenues dans cette table sont ventilées aprés vérification dans les tables "entite_spatiale_ecologique", "point_faune", "personne_est_auteur_donnee", "structure_est_auteur_donnee" et "structure_a_rendu_ese".
Il manque la référence possible à une photo, un échantillon...
L''attribut id_entite est renseigné automatiquement lors de la ventilation des données.
L''attribut regne permet le filtrage des données.
La saise de l''effectif est libre. Il faudra probablerment la cadre à l''usage.
Un seul validateur est stocké.
Une seule commune et une seule localisation aussi.';

CREATE SEQUENCE saisie_observation_id_obs_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE saisie_observation_id_obs_seq OWNED BY saisie_observation.id_obs;

CREATE TABLE suivi_saisie_observation (
    operation text,
    date_operation timestamp without time zone NOT NULL,
    utilisateur text NOT NULL,
    id_obs integer NOT NULL,
    date_obs date,
    date_debut_obs date,
    date_fin_obs date,
    date_textuelle text,
    regne text,
    nom_vern text,
    nom_complet text,
    cd_nom text,
    effectif_textuel text,
    effectif_min bigint,
    effectif_max bigint,
    type_effectif text,
    phenologie text,
    id_waypoint text,
    longitude double precision,
    latitude double precision,
    localisation text,
    observateur text,
    numerisateur integer,
    validateur integer,
    structure text,
    remarque_obs text,
    code_insee text,
    id_lieu_dit text,
    diffusable boolean DEFAULT true,
    "precision" enum_precision,
    statut_validation enum_statut_validation,
    id_etude integer,
    id_protocole integer,
    effectif bigint,
    url_photo text,
    commentaire_photo text,
    decision_validation text,
    heure_obs time without time zone,
    determination enum_determination,
    elevation bigint,
    geometrie public.geometry(Geometry,2154),
    phylum text,
    classe text,
    ordre text,
    famille text,
    nom_valide text,
    qualification enum_qualification[]
);

COMMENT ON TABLE suivi_saisie_observation IS 'Table qui enregistre l''ensemble des actions (type, heure, utilisateur) effectuée sur la table saisie_observation.';

SET search_path = stats, public, pg_catalog;

CREATE VIEW cpt_animalia_annee_mois_numerisateur AS
 SELECT t1.annee,
    t1.num_mois,
    t1.mois,
    t1.numerisateur,
    t1.alias,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_insert
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'INSERT'::text) AND (suivi_saisie_observation.regne = 'Animalia'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_delete
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'DELETE'::text) AND (suivi_saisie_observation.regne = 'Animalia'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t2 USING (annee, num_mois, mois, numerisateur, alias))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) DESC;

CREATE VIEW trois_derniers_mois AS
 SELECT lim3.annee,
    lim3.num_mois,
    lim3.mois
   FROM ( SELECT DISTINCT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois
           FROM saisie.suivi_saisie_observation
          ORDER BY (date_part('year'::text, suivi_saisie_observation.date_operation)) DESC, (date_part('month'::text, suivi_saisie_observation.date_operation)) DESC
         LIMIT 3) lim3;

CREATE VIEW animalia_trois_mois_trois_numerisateurs AS
( SELECT row_number() OVER (ORDER BY t1.annee DESC, t1.num_mois DESC, cpt_animalia_annee_mois_numerisateur.cpt DESC) AS classement,
    t1.annee,
    t1.num_mois,
    t1.mois,
    cpt_animalia_annee_mois_numerisateur.numerisateur,
    cpt_animalia_annee_mois_numerisateur.alias,
    cpt_animalia_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         LIMIT 1) t1
     JOIN cpt_animalia_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_animalia_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t2.annee DESC, t2.num_mois DESC, cpt_animalia_annee_mois_numerisateur.cpt DESC) AS classement,
    t2.annee,
    t2.num_mois,
    t2.mois,
    cpt_animalia_annee_mois_numerisateur.numerisateur,
    cpt_animalia_annee_mois_numerisateur.alias,
    cpt_animalia_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 1
         LIMIT 1) t2
     JOIN cpt_animalia_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_animalia_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t3.annee DESC, t3.num_mois DESC, cpt_animalia_annee_mois_numerisateur.cpt DESC) AS classement,
    t3.annee,
    t3.num_mois,
    t3.mois,
    cpt_animalia_annee_mois_numerisateur.numerisateur,
    cpt_animalia_annee_mois_numerisateur.alias,
    cpt_animalia_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 2
         LIMIT 1) t3
     JOIN cpt_animalia_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_animalia_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
  ORDER BY 2 DESC, 3 DESC, 7 DESC;

CREATE VIEW cpt_cd_nom_annee_mois AS
 SELECT t1.regne,
    t1.cd_nom,
    t1.nom_complet,
    t1.annee,
    t1.num_mois,
    t1.mois,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT suivi_saisie_observation.regne,
            suivi_saisie_observation.cd_nom,
            suivi_saisie_observation.nom_complet,
            date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_insert
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'INSERT'::text)
          GROUP BY suivi_saisie_observation.regne, suivi_saisie_observation.cd_nom, suivi_saisie_observation.nom_complet, (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t1
     LEFT JOIN ( SELECT suivi_saisie_observation.regne,
            suivi_saisie_observation.cd_nom,
            suivi_saisie_observation.nom_complet,
            date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_delete
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'DELETE'::text)
          GROUP BY suivi_saisie_observation.regne, suivi_saisie_observation.cd_nom, suivi_saisie_observation.nom_complet, (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t2 USING (regne, cd_nom, nom_complet, annee, num_mois, mois))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, t1.regne, t1.nom_complet;

CREATE VIEW bilan_cd_nom_regne_mensuel AS
 SELECT cpt_espece_annee_mois.regne,
    cpt_espece_annee_mois.annee,
    cpt_espece_annee_mois.num_mois,
    cpt_espece_annee_mois.mois,
    count(cpt_espece_annee_mois.cd_nom) AS cpt_especes,
    sum(cpt_espece_annee_mois.cpt) AS cpt_obs
   FROM cpt_cd_nom_annee_mois cpt_espece_annee_mois
  GROUP BY cpt_espece_annee_mois.regne, cpt_espece_annee_mois.annee, cpt_espece_annee_mois.num_mois, cpt_espece_annee_mois.mois
  ORDER BY cpt_espece_annee_mois.regne, cpt_espece_annee_mois.annee DESC, cpt_espece_annee_mois.num_mois DESC;

CREATE VIEW cpt_nom_valide_annee_mois AS
 SELECT t1.regne,
    t1.nom_valide,
    t1.annee,
    t1.num_mois,
    t1.mois,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT req1.regne,
            req1.nom_valide,
            date_part('year'::text, req1.date_operation) AS annee,
            date_part('month'::text, req1.date_operation) AS num_mois,
            to_char(req1.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_insert
           FROM ( SELECT suivi_saisie_observation.regne,
                    COALESCE(suivi_saisie_observation.nom_valide, suivi_saisie_observation.nom_complet) AS nom_valide,
                    suivi_saisie_observation.date_operation,
                    suivi_saisie_observation.operation
                   FROM saisie.suivi_saisie_observation) req1
          WHERE (req1.operation = 'INSERT'::text)
          GROUP BY req1.regne, req1.nom_valide, (date_part('year'::text, req1.date_operation)), (date_part('month'::text, req1.date_operation)), (to_char(req1.date_operation, 'TMMonth'::text))) t1
     LEFT JOIN ( SELECT req2.regne,
            req2.nom_valide,
            date_part('year'::text, req2.date_operation) AS annee,
            date_part('month'::text, req2.date_operation) AS num_mois,
            to_char(req2.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_delete
           FROM ( SELECT suivi_saisie_observation.regne,
                    COALESCE(suivi_saisie_observation.nom_valide, suivi_saisie_observation.nom_complet) AS nom_valide,
                    suivi_saisie_observation.date_operation,
                    suivi_saisie_observation.operation
                   FROM saisie.suivi_saisie_observation) req2
          WHERE (req2.operation = 'DELETE'::text)
          GROUP BY req2.regne, req2.nom_valide, (date_part('year'::text, req2.date_operation)), (date_part('month'::text, req2.date_operation)), (to_char(req2.date_operation, 'TMMonth'::text))) t2 USING (regne, nom_valide, annee, num_mois, mois))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, t1.regne, t1.nom_valide;

CREATE VIEW bilan_nom_valide_regne_mensuel AS
 SELECT cpt_reference_annee_mois.regne,
    cpt_reference_annee_mois.annee,
    cpt_reference_annee_mois.num_mois,
    cpt_reference_annee_mois.mois,
    count(cpt_reference_annee_mois.nom_valide) AS cpt_especes,
    cpt_nom_valide_suppl(cpt_reference_annee_mois.regne, (cpt_reference_annee_mois.num_mois)::integer, (cpt_reference_annee_mois.annee)::integer) AS cpt_nom_valide_suppl,
    sum(cpt_reference_annee_mois.cpt) AS cpt_obs
   FROM cpt_nom_valide_annee_mois cpt_reference_annee_mois
  GROUP BY cpt_reference_annee_mois.regne, cpt_reference_annee_mois.annee, cpt_reference_annee_mois.num_mois, cpt_reference_annee_mois.mois
  ORDER BY cpt_reference_annee_mois.regne, cpt_reference_annee_mois.annee DESC, cpt_reference_annee_mois.num_mois DESC;

CREATE VIEW cpt_fungi_annee_mois_numerisateur AS
 SELECT t1.annee,
    t1.num_mois,
    t1.mois,
    t1.numerisateur,
    t1.alias,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_insert
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'INSERT'::text) AND (suivi_saisie_observation.regne = 'Fungi'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_delete
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'DELETE'::text) AND (suivi_saisie_observation.regne = 'Fungi'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t2 USING (annee, num_mois, mois, numerisateur, alias))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) DESC;

CREATE VIEW cpt_habitat_annee_mois_numerisateur AS
 SELECT t1.annee,
    t1.num_mois,
    t1.mois,
    t1.numerisateur,
    t1.alias,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_insert
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'INSERT'::text) AND (suivi_saisie_observation.regne = 'Habitat'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_delete
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'DELETE'::text) AND (suivi_saisie_observation.regne = 'Habitat'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t2 USING (annee, num_mois, mois, numerisateur, alias))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) DESC;

CREATE VIEW cpt_plantae_annee_mois_numerisateur AS
 SELECT t1.annee,
    t1.num_mois,
    t1.mois,
    t1.numerisateur,
    t1.alias,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt
   FROM (( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_insert
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'INSERT'::text) AND (suivi_saisie_observation.regne = 'Plantae'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            suivi_saisie_observation.numerisateur,
            ((personne.prenom || ' '::text) || personne.nom) AS alias,
            count(*) AS cpt_delete
           FROM (saisie.suivi_saisie_observation
             LEFT JOIN md.personne ON ((personne.id_personne = suivi_saisie_observation.numerisateur)))
          WHERE ((suivi_saisie_observation.operation = 'DELETE'::text) AND (suivi_saisie_observation.regne = 'Plantae'::text))
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text)), suivi_saisie_observation.numerisateur, ((personne.prenom || ' '::text) || personne.nom)) t2 USING (annee, num_mois, mois, numerisateur, alias))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) DESC;

CREATE VIEW fungi_trois_mois_trois_numerisateurs AS
( SELECT row_number() OVER (ORDER BY t1.annee DESC, t1.num_mois DESC, cpt_fungi_annee_mois_numerisateur.cpt DESC) AS classement,
    t1.annee,
    t1.num_mois,
    t1.mois,
    cpt_fungi_annee_mois_numerisateur.numerisateur,
    cpt_fungi_annee_mois_numerisateur.alias,
    cpt_fungi_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         LIMIT 1) t1
     JOIN cpt_fungi_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_fungi_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t2.annee DESC, t2.num_mois DESC, cpt_fungi_annee_mois_numerisateur.cpt DESC) AS classement,
    t2.annee,
    t2.num_mois,
    t2.mois,
    cpt_fungi_annee_mois_numerisateur.numerisateur,
    cpt_fungi_annee_mois_numerisateur.alias,
    cpt_fungi_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 1
         LIMIT 1) t2
     JOIN cpt_fungi_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_fungi_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t3.annee DESC, t3.num_mois DESC, cpt_fungi_annee_mois_numerisateur.cpt DESC) AS classement,
    t3.annee,
    t3.num_mois,
    t3.mois,
    cpt_fungi_annee_mois_numerisateur.numerisateur,
    cpt_fungi_annee_mois_numerisateur.alias,
    cpt_fungi_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 2
         LIMIT 1) t3
     JOIN cpt_fungi_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_fungi_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
  ORDER BY 2 DESC, 3 DESC, 7 DESC;

CREATE VIEW habitat_trois_mois_trois_numerisateurs AS
( SELECT row_number() OVER (ORDER BY t1.annee DESC, t1.num_mois DESC, cpt_habitat_annee_mois_numerisateur.cpt DESC) AS classement,
    t1.annee,
    t1.num_mois,
    t1.mois,
    cpt_habitat_annee_mois_numerisateur.numerisateur,
    cpt_habitat_annee_mois_numerisateur.alias,
    cpt_habitat_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         LIMIT 1) t1
     JOIN cpt_habitat_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_habitat_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t2.annee DESC, t2.num_mois DESC, cpt_habitat_annee_mois_numerisateur.cpt DESC) AS classement,
    t2.annee,
    t2.num_mois,
    t2.mois,
    cpt_habitat_annee_mois_numerisateur.numerisateur,
    cpt_habitat_annee_mois_numerisateur.alias,
    cpt_habitat_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 1
         LIMIT 1) t2
     JOIN cpt_habitat_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_habitat_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t3.annee DESC, t3.num_mois DESC, cpt_habitat_annee_mois_numerisateur.cpt DESC) AS classement,
    t3.annee,
    t3.num_mois,
    t3.mois,
    cpt_habitat_annee_mois_numerisateur.numerisateur,
    cpt_habitat_annee_mois_numerisateur.alias,
    cpt_habitat_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 2
         LIMIT 1) t3
     JOIN cpt_habitat_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_habitat_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
  ORDER BY 2 DESC, 3 DESC, 7 DESC;

CREATE VIEW plantae_trois_mois_trois_numerisateurs AS
( SELECT row_number() OVER (ORDER BY t1.annee DESC, t1.num_mois DESC, cpt_plantae_annee_mois_numerisateur.cpt DESC) AS classement,
    t1.annee,
    t1.num_mois,
    t1.mois,
    cpt_plantae_annee_mois_numerisateur.numerisateur,
    cpt_plantae_annee_mois_numerisateur.alias,
    cpt_plantae_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         LIMIT 1) t1
     JOIN cpt_plantae_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_plantae_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t2.annee DESC, t2.num_mois DESC, cpt_plantae_annee_mois_numerisateur.cpt DESC) AS classement,
    t2.annee,
    t2.num_mois,
    t2.mois,
    cpt_plantae_annee_mois_numerisateur.numerisateur,
    cpt_plantae_annee_mois_numerisateur.alias,
    cpt_plantae_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 1
         LIMIT 1) t2
     JOIN cpt_plantae_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_plantae_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
UNION
( SELECT row_number() OVER (ORDER BY t3.annee DESC, t3.num_mois DESC, cpt_plantae_annee_mois_numerisateur.cpt DESC) AS classement,
    t3.annee,
    t3.num_mois,
    t3.mois,
    cpt_plantae_annee_mois_numerisateur.numerisateur,
    cpt_plantae_annee_mois_numerisateur.alias,
    cpt_plantae_annee_mois_numerisateur.cpt
   FROM (( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois
           FROM trois_derniers_mois
         OFFSET 2
         LIMIT 1) t3
     JOIN cpt_plantae_annee_mois_numerisateur USING (annee, num_mois, mois))
  ORDER BY cpt_plantae_annee_mois_numerisateur.cpt DESC
 LIMIT 3)
  ORDER BY 2 DESC, 3 DESC, 7 DESC;

CREATE VIEW classement_trois_derniers_mois AS
 SELECT row_number() OVER (ORDER BY t.annee DESC, t.num_mois DESC, classement) AS id,
    t.annee,
    t.mois,
    classement,
    t1.alias AS alias_animalia,
    t1.cpt AS cpt_animalia,
    t2.alias AS alias_plantae,
    t2.cpt AS cpt_plantae,
    t3.alias AS alias_fungi,
    t3.cpt AS cpt_fungi,
    t4.alias AS alias_habitat,
    t4.cpt AS cpt_habitat
   FROM ((((( SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois,
            1 AS classement
           FROM trois_derniers_mois
        UNION
         SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois,
            2 AS classement
           FROM trois_derniers_mois
        UNION
         SELECT trois_derniers_mois.annee,
            trois_derniers_mois.num_mois,
            trois_derniers_mois.mois,
            3 AS classement
           FROM trois_derniers_mois) t
     LEFT JOIN animalia_trois_mois_trois_numerisateurs t1 USING (annee, num_mois, mois, classement))
     LEFT JOIN plantae_trois_mois_trois_numerisateurs t2 USING (annee, num_mois, mois, classement))
     LEFT JOIN fungi_trois_mois_trois_numerisateurs t3 USING (annee, num_mois, mois, classement))
     LEFT JOIN habitat_trois_mois_trois_numerisateurs t4 USING (annee, num_mois, mois, classement))
  ORDER BY t.annee DESC, t.num_mois DESC, classement;

CREATE VIEW cumul_cd_nom_regne_mensuel AS
 SELECT row_number() OVER (ORDER BY t.regne, t.annee, t.num_mois) AS id,
    t.regne,
    t.annee,
    t.mois,
    t.cpt_especes,
    t.cumul_especes,
    t.cpt_obs,
    t.cumul_obs
   FROM (( SELECT bilan_regne_mensuel.regne,
            bilan_regne_mensuel.annee,
            bilan_regne_mensuel.num_mois,
            bilan_regne_mensuel.mois,
            bilan_regne_mensuel.cpt_especes,
            bilan_regne_mensuel.cpt_obs,
            sum(bilan_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_regne_mensuel.cpt_especes) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_especes
           FROM bilan_cd_nom_regne_mensuel bilan_regne_mensuel
          WHERE (bilan_regne_mensuel.regne = 'Animalia'::text)
          ORDER BY bilan_regne_mensuel.regne, bilan_regne_mensuel.annee, bilan_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_regne_mensuel.regne,
            bilan_regne_mensuel.annee,
            bilan_regne_mensuel.num_mois,
            bilan_regne_mensuel.mois,
            bilan_regne_mensuel.cpt_especes,
            bilan_regne_mensuel.cpt_obs,
            sum(bilan_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_regne_mensuel.cpt_especes) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_especes
           FROM bilan_cd_nom_regne_mensuel bilan_regne_mensuel
          WHERE (bilan_regne_mensuel.regne = 'Plantae'::text)
          ORDER BY bilan_regne_mensuel.regne, bilan_regne_mensuel.annee, bilan_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_regne_mensuel.regne,
            bilan_regne_mensuel.annee,
            bilan_regne_mensuel.num_mois,
            bilan_regne_mensuel.mois,
            bilan_regne_mensuel.cpt_especes,
            bilan_regne_mensuel.cpt_obs,
            sum(bilan_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_regne_mensuel.cpt_especes) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_especes
           FROM bilan_cd_nom_regne_mensuel bilan_regne_mensuel
          WHERE (bilan_regne_mensuel.regne = 'Fungi'::text)
          ORDER BY bilan_regne_mensuel.regne, bilan_regne_mensuel.annee, bilan_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_regne_mensuel.regne,
            bilan_regne_mensuel.annee,
            bilan_regne_mensuel.num_mois,
            bilan_regne_mensuel.mois,
            bilan_regne_mensuel.cpt_especes,
            bilan_regne_mensuel.cpt_obs,
            sum(bilan_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_regne_mensuel.cpt_especes) OVER (PARTITION BY bilan_regne_mensuel.annee ORDER BY bilan_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_especes
           FROM bilan_cd_nom_regne_mensuel bilan_regne_mensuel
          WHERE (bilan_regne_mensuel.regne = 'Habitat'::text)
          ORDER BY bilan_regne_mensuel.regne, bilan_regne_mensuel.annee, bilan_regne_mensuel.num_mois)) t
  ORDER BY t.regne, t.annee, t.num_mois;

CREATE VIEW cumul_nom_valide_regne_mensuel AS
 SELECT row_number() OVER (ORDER BY t.regne, t.annee, t.num_mois) AS id,
    t.regne,
    t.annee,
    t.mois,
    t.cpt_especes,
    t.cpt_nom_valide_suppl,
    t.cumul_nom_valide_suppl,
    t.cpt_obs,
    t.cumul_obs
   FROM (( SELECT bilan_reference_regne_mensuel.cpt_nom_valide_suppl,
            bilan_reference_regne_mensuel.regne,
            bilan_reference_regne_mensuel.annee,
            bilan_reference_regne_mensuel.num_mois,
            bilan_reference_regne_mensuel.mois,
            bilan_reference_regne_mensuel.cpt_especes,
            bilan_reference_regne_mensuel.cpt_obs,
            sum(bilan_reference_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_reference_regne_mensuel.cpt_nom_valide_suppl) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_nom_valide_suppl
           FROM bilan_nom_valide_regne_mensuel bilan_reference_regne_mensuel
          WHERE (bilan_reference_regne_mensuel.regne = 'Animalia'::text)
          ORDER BY bilan_reference_regne_mensuel.regne, bilan_reference_regne_mensuel.annee, bilan_reference_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_reference_regne_mensuel.cpt_nom_valide_suppl,
            bilan_reference_regne_mensuel.regne,
            bilan_reference_regne_mensuel.annee,
            bilan_reference_regne_mensuel.num_mois,
            bilan_reference_regne_mensuel.mois,
            bilan_reference_regne_mensuel.cpt_especes,
            bilan_reference_regne_mensuel.cpt_obs,
            sum(bilan_reference_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_reference_regne_mensuel.cpt_nom_valide_suppl) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_nom_valide_suppl
           FROM bilan_nom_valide_regne_mensuel bilan_reference_regne_mensuel
          WHERE (bilan_reference_regne_mensuel.regne = 'Plantae'::text)
          ORDER BY bilan_reference_regne_mensuel.regne, bilan_reference_regne_mensuel.annee, bilan_reference_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_reference_regne_mensuel.cpt_nom_valide_suppl,
            bilan_reference_regne_mensuel.regne,
            bilan_reference_regne_mensuel.annee,
            bilan_reference_regne_mensuel.num_mois,
            bilan_reference_regne_mensuel.mois,
            bilan_reference_regne_mensuel.cpt_especes,
            bilan_reference_regne_mensuel.cpt_obs,
            sum(bilan_reference_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_reference_regne_mensuel.cpt_nom_valide_suppl) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_nom_valide_suppl
           FROM bilan_nom_valide_regne_mensuel bilan_reference_regne_mensuel
          WHERE (bilan_reference_regne_mensuel.regne = 'Fungi'::text)
          ORDER BY bilan_reference_regne_mensuel.regne, bilan_reference_regne_mensuel.annee, bilan_reference_regne_mensuel.num_mois)
        UNION
        ( SELECT bilan_reference_regne_mensuel.cpt_nom_valide_suppl,
            bilan_reference_regne_mensuel.regne,
            bilan_reference_regne_mensuel.annee,
            bilan_reference_regne_mensuel.num_mois,
            bilan_reference_regne_mensuel.mois,
            bilan_reference_regne_mensuel.cpt_especes,
            bilan_reference_regne_mensuel.cpt_obs,
            sum(bilan_reference_regne_mensuel.cpt_obs) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_obs,
            sum(bilan_reference_regne_mensuel.cpt_nom_valide_suppl) OVER (PARTITION BY bilan_reference_regne_mensuel.annee ORDER BY bilan_reference_regne_mensuel.num_mois ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul_nom_valide_suppl
           FROM bilan_nom_valide_regne_mensuel bilan_reference_regne_mensuel
          WHERE (bilan_reference_regne_mensuel.regne = 'Habitat'::text)
          ORDER BY bilan_reference_regne_mensuel.regne, bilan_reference_regne_mensuel.annee, bilan_reference_regne_mensuel.num_mois)) t
  ORDER BY t.regne, t.annee, t.num_mois;

CREATE VIEW total_mensuel_numerisateur AS
 SELECT t1.annee,
    t1.num_mois,
    t1.mois,
    (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) AS cpt,
    personne.nom,
    personne.prenom
   FROM ((( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            count(*) AS cpt_insert,
            suivi_saisie_observation.numerisateur
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'INSERT'::text)
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), suivi_saisie_observation.numerisateur, (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            date_part('month'::text, suivi_saisie_observation.date_operation) AS num_mois,
            count(*) AS cpt_delete,
            suivi_saisie_observation.numerisateur
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'DELETE'::text)
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (date_part('month'::text, suivi_saisie_observation.date_operation)), suivi_saisie_observation.numerisateur, (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t2 USING (annee, num_mois, numerisateur, mois))
     LEFT JOIN md.personne ON ((personne.id_personne = t1.numerisateur)))
  WHERE ((COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) > 0)
  ORDER BY t1.annee DESC, t1.num_mois DESC, (COALESCE(t1.cpt_insert, (0)::bigint) - COALESCE(t2.cpt_delete, (0)::bigint)) DESC;

CREATE VIEW meilleur_numerisateur_mois AS
 SELECT total_mensuel_numerisateur.cpt,
    total_mensuel_numerisateur.annee,
    total_mensuel_numerisateur.mois,
    total_mensuel_numerisateur.nom,
    total_mensuel_numerisateur.prenom
   FROM (total_mensuel_numerisateur
     JOIN ( SELECT max(total_mensuel_numerisateur_1.cpt) AS cpt,
            total_mensuel_numerisateur_1.annee,
            total_mensuel_numerisateur_1.num_mois
           FROM total_mensuel_numerisateur total_mensuel_numerisateur_1
          GROUP BY total_mensuel_numerisateur_1.annee, total_mensuel_numerisateur_1.num_mois) t USING (cpt, annee, num_mois))
  ORDER BY total_mensuel_numerisateur.annee DESC, total_mensuel_numerisateur.num_mois DESC;

CREATE VIEW total_mensuel_global AS
 SELECT t1.annee,
    t1.mois,
    (t1.cpt_insert - t2.cpt_delete) AS cpt
   FROM (( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_insert
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'INSERT'::text)
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t1
     LEFT JOIN ( SELECT date_part('year'::text, suivi_saisie_observation.date_operation) AS annee,
            to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text) AS mois,
            count(*) AS cpt_delete
           FROM saisie.suivi_saisie_observation
          WHERE (suivi_saisie_observation.operation = 'DELETE'::text)
          GROUP BY (date_part('year'::text, suivi_saisie_observation.date_operation)), (to_char(suivi_saisie_observation.date_operation, 'TMMonth'::text))) t2 USING (annee, mois));

SET search_path = md, public, pg_catalog;

ALTER TABLE ONLY personne ALTER COLUMN id_personne SET DEFAULT nextval('personne_id_personne_seq'::regclass);

ALTER TABLE ONLY protocole ALTER COLUMN id_protocole SET DEFAULT nextval('protocole_id_protocole_seq'::regclass);

ALTER TABLE ONLY structure ALTER COLUMN id_structure SET DEFAULT nextval('structure_id_structure_seq'::regclass);

SET search_path = saisie, public, pg_catalog;

ALTER TABLE ONLY saisie_observation ALTER COLUMN id_obs SET DEFAULT nextval('saisie_observation_id_obs_seq'::regclass);

SET search_path = ign_bd_topo, public, pg_catalog;

ALTER TABLE ONLY commune
    ADD CONSTRAINT commune_nom_depart_key UNIQUE (nom, depart);

ALTER TABLE ONLY commune
    ADD CONSTRAINT commune_pkey PRIMARY KEY (code_insee);

ALTER TABLE ONLY lieu_dit
    ADD CONSTRAINT lieu_dit_pkey PRIMARY KEY (id);

SET search_path = inpn, public, pg_catalog;

ALTER TABLE ONLY taxref
    ADD CONSTRAINT taxref_pkey PRIMARY KEY (cd_nom);

ALTER TABLE ONLY typo_corine_biotopes
    ADD CONSTRAINT typo_corine_biotopes_pkey PRIMARY KEY (cd_cb);

SET search_path = md, public, pg_catalog;

ALTER TABLE ONLY etude
    ADD CONSTRAINT etude_nom_etude_key UNIQUE (nom_etude);

ALTER TABLE ONLY etude
    ADD CONSTRAINT etude_pkey PRIMARY KEY (id_etude);

ALTER TABLE ONLY personne
    ADD CONSTRAINT personne_email_key UNIQUE (email);

ALTER TABLE ONLY personne
    ADD CONSTRAINT personne_pkey PRIMARY KEY (id_personne);

ALTER TABLE ONLY personne
    ADD CONSTRAINT personne_prenom_nom_key UNIQUE (prenom, nom);

ALTER TABLE ONLY protocole
    ADD CONSTRAINT protocole_libelle_key UNIQUE (libelle);

ALTER TABLE ONLY protocole
    ADD CONSTRAINT protocole_pkey PRIMARY KEY (id_protocole);

ALTER TABLE ONLY structure
    ADD CONSTRAINT structure_nom_structure_key UNIQUE (nom_structure);

ALTER TABLE ONLY structure
    ADD CONSTRAINT structure_pkey PRIMARY KEY (id_structure);

SET search_path = saisie, public, pg_catalog;

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_pkey PRIMARY KEY (id_obs);

ALTER TABLE ONLY suivi_saisie_observation
    ADD CONSTRAINT suivi_saisie_observation_pkey PRIMARY KEY (date_operation, utilisateur, id_obs);

SET search_path = ign_bd_topo, public, pg_catalog;
CREATE INDEX commune_geometrie_idx ON commune USING gist (geometrie);
CREATE INDEX commune_nom_idx ON commune USING btree (nom);
CREATE INDEX lieu_dit_geometrie_idx ON lieu_dit USING gist (geometrie);
CREATE INDEX lieu_dit_nom_idx ON lieu_dit USING btree (nom);

SET search_path = inpn, public, pg_catalog;
CREATE INDEX taxref_cd_ref_idx ON taxref USING btree (cd_ref);
CREATE INDEX taxref_lb_nom_idx ON taxref USING gist (lb_nom COLLATE pg_catalog."default" gist_trgm_ops);
CREATE INDEX taxref_nom_complet_idx ON taxref USING gist (nom_complet COLLATE pg_catalog."default" gist_trgm_ops);
CREATE INDEX taxref_nom_vern_idx ON taxref USING gist (nom_vern COLLATE pg_catalog."default" gist_trgm_ops);
CREATE INDEX taxref_regne_idx ON taxref USING gist (regne COLLATE pg_catalog."default" gist_trgm_ops);
CREATE INDEX typo_corine_biotopes_lb_cb97_fr_idx ON typo_corine_biotopes USING btree (lb_cb97_fr);

SET search_path = md, public, pg_catalog;
CREATE INDEX etude_nom_etude_idx ON etude USING btree (nom_etude);
CREATE INDEX personne_createur_idx ON personne USING btree (createur);
CREATE INDEX personne_email_idx ON personne USING btree (email);
CREATE INDEX personne_id_structure_idx ON personne USING btree (id_structure);
CREATE INDEX personne_role_idx ON personne USING btree (role);
CREATE INDEX personne_specialite_idx ON personne USING btree (specialite);
CREATE INDEX protocole_libelle_idx ON protocole USING btree (libelle);
CREATE INDEX structure_createur_idx ON structure USING btree (createur);
CREATE INDEX structure_diffusable_idx ON structure USING btree (diffusable);
CREATE INDEX structure_nom_structure_idx ON structure USING btree (nom_structure);

SET search_path = saisie, public, pg_catalog;
CREATE INDEX saisie_observation_cd_nom_idx ON saisie_observation USING btree (cd_nom);
CREATE INDEX saisie_observation_classe_idx ON saisie_observation USING btree (classe);
CREATE INDEX saisie_observation_code_insee_idx ON saisie_observation USING btree (code_insee);
CREATE INDEX saisie_observation_diffusable_idx ON saisie_observation USING btree (diffusable);
CREATE INDEX saisie_observation_famille_idx ON saisie_observation USING btree (famille);
CREATE INDEX saisie_observation_geometrie_idx ON saisie_observation USING gist (geometrie);
CREATE INDEX saisie_observation_id_etude_idx ON saisie_observation USING btree (id_etude);
CREATE INDEX saisie_observation_id_lieu_dit_idx ON saisie_observation USING btree (id_lieu_dit);
CREATE INDEX saisie_observation_id_protocole_idx ON saisie_observation USING btree (id_protocole);
CREATE INDEX saisie_observation_liste_observateurs_idx ON saisie_observation USING gist (md.liste_nom_auteur(observateur) gist_trgm_ops);
CREATE INDEX saisie_observation_nom_complet_idx ON saisie_observation USING btree (nom_complet);
CREATE INDEX saisie_observation_nom_valide_idx ON saisie_observation USING btree (nom_valide);
CREATE INDEX saisie_observation_nom_vern_idx ON saisie_observation USING btree (nom_vern);
CREATE INDEX saisie_observation_numerisateur_idx ON saisie_observation USING btree (numerisateur);
CREATE INDEX saisie_observation_ordre_idx ON saisie_observation USING btree (ordre);
CREATE INDEX saisie_observation_phylum_idx ON saisie_observation USING btree (phylum);
CREATE INDEX saisie_observation_regne_idx ON saisie_observation USING btree (regne);
CREATE INDEX saisie_observation_statut_validation_idx ON saisie_observation USING btree (statut_validation);
CREATE INDEX saisie_observation_validateur_idx ON saisie_observation USING btree (validateur);

SET search_path = md, public, pg_catalog;

CREATE TRIGGER md_creation_observateur AFTER INSERT OR DELETE OR UPDATE ON personne FOR EACH ROW EXECUTE PROCEDURE creation_modification_observateur();

SET search_path = saisie, public, pg_catalog;

CREATE TRIGGER suivi_saisie_observation AFTER INSERT OR DELETE OR UPDATE ON saisie_observation FOR EACH ROW EXECUTE PROCEDURE alimente_suivi_saisie_observation();

SET search_path = inpn, public, pg_catalog;

ALTER TABLE ONLY taxref
    ADD CONSTRAINT taxref_cd_ref_fkey FOREIGN KEY (cd_ref) REFERENCES taxref(cd_nom);

SET search_path = md, public, pg_catalog;

ALTER TABLE ONLY personne
    ADD CONSTRAINT personne_createur_fkey FOREIGN KEY (createur) REFERENCES personne(id_personne);

ALTER TABLE ONLY personne
    ADD CONSTRAINT personne_id_structure_fkey FOREIGN KEY (id_structure) REFERENCES structure(id_structure);

ALTER TABLE ONLY structure
    ADD CONSTRAINT structure_createur_fkey FOREIGN KEY (createur) REFERENCES personne(id_personne);

SET search_path = saisie, public, pg_catalog;

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_code_insee_fkey FOREIGN KEY (code_insee) REFERENCES ign_bd_topo.commune(code_insee);

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_id_etude_fkey FOREIGN KEY (id_etude) REFERENCES md.etude(id_etude);

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_id_lieu_dit_fkey FOREIGN KEY (id_lieu_dit) REFERENCES ign_bd_topo.lieu_dit(id);

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_id_protocole_fkey FOREIGN KEY (id_protocole) REFERENCES md.protocole(id_protocole);

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_numerisateur_fkey FOREIGN KEY (numerisateur) REFERENCES md.personne(id_personne);

ALTER TABLE ONLY saisie_observation
    ADD CONSTRAINT saisie_observation_validateur_fkey FOREIGN KEY (validateur) REFERENCES md.personne(id_personne);

REVOKE ALL ON SCHEMA ign_bd_topo FROM PUBLIC;
REVOKE ALL ON SCHEMA ign_bd_topo FROM dba;
GRANT ALL ON SCHEMA ign_bd_topo TO dba;
GRANT USAGE ON SCHEMA ign_bd_topo TO db_name_gr_consult;

REVOKE ALL ON SCHEMA inpn FROM PUBLIC;
REVOKE ALL ON SCHEMA inpn FROM dba;
GRANT ALL ON SCHEMA inpn TO dba;
GRANT USAGE ON SCHEMA inpn TO db_name_gr_consult;

REVOKE ALL ON SCHEMA md FROM PUBLIC;
REVOKE ALL ON SCHEMA md FROM dba;
GRANT ALL ON SCHEMA md TO dba;
GRANT USAGE ON SCHEMA md TO db_name_gr_consult;
GRANT USAGE ON SCHEMA md TO db_name_cnx;

REVOKE ALL ON SCHEMA outils FROM PUBLIC;
REVOKE ALL ON SCHEMA outils FROM dba;
GRANT ALL ON SCHEMA outils TO dba;
GRANT USAGE ON SCHEMA outils TO db_name_gr_consult;
GRANT USAGE ON SCHEMA outils TO db_name_cnx;

REVOKE ALL ON SCHEMA saisie FROM PUBLIC;
REVOKE ALL ON SCHEMA saisie FROM dba;
GRANT ALL ON SCHEMA saisie TO dba;
GRANT USAGE ON SCHEMA saisie TO db_name_gr_consult;

SET search_path = outils, public, pg_catalog;

REVOKE ALL ON FUNCTION get_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION get_user() FROM dba;
GRANT ALL ON FUNCTION get_user() TO dba;
GRANT ALL ON FUNCTION get_user() TO PUBLIC;
GRANT ALL ON FUNCTION get_user() TO db_name_gr_amateur;
GRANT ALL ON FUNCTION get_user() TO db_name_cnx;

REVOKE ALL ON FUNCTION set_user(myid_user text) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_user(myid_user text) FROM dba;
GRANT ALL ON FUNCTION set_user(myid_user text) TO dba;
GRANT ALL ON FUNCTION set_user(myid_user text) TO PUBLIC;
GRANT ALL ON FUNCTION set_user(myid_user text) TO db_name_gr_amateur;
GRANT ALL ON FUNCTION set_user(myid_user text) TO db_name_cnx;

SET search_path = ign_bd_topo, public, pg_catalog;

REVOKE ALL ON TABLE commune FROM PUBLIC;
REVOKE ALL ON TABLE commune FROM dba;
GRANT ALL ON TABLE commune TO dba;
GRANT SELECT ON TABLE commune TO db_name_gr_consult;

REVOKE ALL ON TABLE lieu_dit FROM PUBLIC;
REVOKE ALL ON TABLE lieu_dit FROM dba;
GRANT ALL ON TABLE lieu_dit TO dba;
GRANT SELECT ON TABLE lieu_dit TO db_name_gr_consult;

SET search_path = inpn, public, pg_catalog;

REVOKE ALL ON TABLE taxref FROM PUBLIC;
REVOKE ALL ON TABLE taxref FROM dba;
GRANT ALL ON TABLE taxref TO dba;
GRANT SELECT ON TABLE taxref TO db_name_gr_consult;

REVOKE ALL ON TABLE typo_corine_biotopes FROM PUBLIC;
REVOKE ALL ON TABLE typo_corine_biotopes FROM dba;
GRANT ALL ON TABLE typo_corine_biotopes TO dba;
GRANT SELECT ON TABLE typo_corine_biotopes TO db_name_gr_consult;

SET search_path = md, public, pg_catalog;

REVOKE ALL ON SEQUENCE etude_id_etude_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE etude_id_etude_seq FROM dba;
GRANT ALL ON SEQUENCE etude_id_etude_seq TO dba;
GRANT USAGE ON SEQUENCE etude_id_etude_seq TO db_name_gr_admin;

REVOKE ALL ON TABLE etude FROM PUBLIC;
REVOKE ALL ON TABLE etude FROM dba;
GRANT ALL ON TABLE etude TO dba;
GRANT SELECT ON TABLE etude TO db_name_gr_consult;
GRANT INSERT,DELETE,UPDATE ON TABLE etude TO db_name_gr_admin;

REVOKE ALL ON TABLE personne FROM PUBLIC;
REVOKE ALL ON TABLE personne FROM dba;
GRANT ALL ON TABLE personne TO dba;
GRANT SELECT ON TABLE personne TO db_name_gr_consult;
GRANT SELECT ON TABLE personne TO db_name_cnx;
GRANT INSERT,UPDATE ON TABLE personne TO db_name_gr_amateur;

REVOKE ALL ON SEQUENCE personne_id_personne_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE personne_id_personne_seq FROM dba;
GRANT ALL ON SEQUENCE personne_id_personne_seq TO dba;
GRANT USAGE ON SEQUENCE personne_id_personne_seq TO db_name_gr_amateur;

REVOKE ALL ON TABLE protocole FROM PUBLIC;
REVOKE ALL ON TABLE protocole FROM dba;
GRANT ALL ON TABLE protocole TO dba;
GRANT SELECT ON TABLE protocole TO db_name_gr_consult;
GRANT INSERT,DELETE,UPDATE ON TABLE protocole TO db_name_gr_admin;

REVOKE ALL ON SEQUENCE protocole_id_protocole_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE protocole_id_protocole_seq FROM dba;
GRANT ALL ON SEQUENCE protocole_id_protocole_seq TO dba;
GRANT USAGE ON SEQUENCE protocole_id_protocole_seq TO db_name_gr_admin;

REVOKE ALL ON TABLE structure FROM PUBLIC;
REVOKE ALL ON TABLE structure FROM dba;
GRANT ALL ON TABLE structure TO dba;
GRANT SELECT ON TABLE structure TO db_name_gr_consult;
GRANT INSERT,UPDATE ON TABLE structure TO db_name_gr_amateur;
GRANT SELECT ON TABLE structure TO db_name_cnx;

REVOKE ALL ON SEQUENCE structure_id_structure_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE structure_id_structure_seq FROM dba;
GRANT ALL ON SEQUENCE structure_id_structure_seq TO dba;
GRANT USAGE ON SEQUENCE structure_id_structure_seq TO db_name_gr_amateur;

SET search_path = saisie, public, pg_catalog;

REVOKE ALL ON TABLE saisie_observation FROM PUBLIC;
REVOKE ALL ON TABLE saisie_observation FROM dba;
GRANT ALL ON TABLE saisie_observation TO dba;
GRANT SELECT ON TABLE saisie_observation TO db_name_gr_consult;
GRANT INSERT,DELETE,UPDATE ON TABLE saisie_observation TO db_name_gr_admin;

REVOKE ALL(validateur) ON TABLE saisie_observation FROM PUBLIC;
REVOKE ALL(validateur) ON TABLE saisie_observation FROM dba;
GRANT UPDATE(validateur) ON TABLE saisie_observation TO db_name_gr_expert;

REVOKE ALL(statut_validation) ON TABLE saisie_observation FROM PUBLIC;
REVOKE ALL(statut_validation) ON TABLE saisie_observation FROM dba;
GRANT UPDATE(statut_validation) ON TABLE saisie_observation TO db_name_gr_expert;

REVOKE ALL(decision_validation) ON TABLE saisie_observation FROM PUBLIC;
REVOKE ALL(decision_validation) ON TABLE saisie_observation FROM dba;
GRANT UPDATE(decision_validation) ON TABLE saisie_observation TO db_name_gr_expert;

REVOKE ALL ON SEQUENCE saisie_observation_id_obs_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE saisie_observation_id_obs_seq FROM dba;
GRANT ALL ON SEQUENCE saisie_observation_id_obs_seq TO dba;
GRANT USAGE ON SEQUENCE saisie_observation_id_obs_seq TO db_name_gr_amateur;

REVOKE ALL ON TABLE suivi_saisie_observation FROM PUBLIC;
REVOKE ALL ON TABLE suivi_saisie_observation FROM dba;
GRANT ALL ON TABLE suivi_saisie_observation TO dba;
GRANT SELECT,INSERT ON TABLE suivi_saisie_observation TO db_name_gr_amateur;

