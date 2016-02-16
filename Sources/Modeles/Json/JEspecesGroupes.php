<?php
    if (!isset($_SESSION)) {
        session_start();
    }
    require_once '../../Configuration/ConfigUtilisee.php';
    include_once '../' . LIB . '/jsonwrapper/jsonwrapper.php';
    require_once '../../Modeles/Classes/ClassCnxPgObsOcc.php';
    require_once '../../' . $configInstance . '/PostGreSQL.php';
    require_once '../../Securite/Decrypt.php';
    
    
    $cnxPgObsOcc = new CnxPgObsOcc();
    
    $req= "SELECT DISTINCT id_liste ". 
          "FROM taxonomie.cor_taxon_liste l ".
          "JOIN taxonomie.bib_taxons t  ".
          "ON t.id_taxon = l.id_taxon ".
          "WHERE cd_nom = " . $_REQUEST['cd_nom'];

    $rs = $cnxPgObsOcc->executeSql($req);
    $arr = array();
    while ($obj = pg_fetch_object($rs)) {
      $arr[] = $obj->id_liste;
    }
    echo json_encode($arr);
    unset($cnxPgObsOcc);
?>
