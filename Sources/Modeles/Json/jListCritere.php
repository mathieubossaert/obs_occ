<?php
    require_once '../../Configuration/ConfigUtilisee.php';
    include_once '../' . LIB . '/jsonwrapper/jsonwrapper.php';
    require_once '../../Modeles/Classes/ClassCnxPgObsOcc.php';
    
    $cnxPgObsOcc = new CnxPgObsOcc();
    $req = "SELECT id_critere, nom_critere
            FROM taxonomie.bib_criteres_valeur
            WHERE id_liste_c= ".  $_REQUEST['id_liste'] ." ; ";
    $rs = $cnxPgObsOcc->executeSql($req);
    $arr = array();
    while ($obj = pg_fetch_object($rs)) {
        $arr[] = $obj;
    }
    echo json_encode($arr);
    unset($cnxPgObsOcc);
?>
