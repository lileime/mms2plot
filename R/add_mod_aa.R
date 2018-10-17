# add modAA information to aa_mw_table and return aa_mw_mod_table
add_mod_aa<-function(mod_parameter_xml, MS2FileName, aa_mw_table, mqpar){
  #browser()
  
  #  Modifications=c("Acetyl (Protein N-term),Phospho (STY)", "Unmodified", "Phospho (STY)", "2 Phospho (STY)", "", NA)
  mqpar = subset(mqpar, grepl(tools::file_path_sans_ext(MS2FileName), tools::file_path_sans_ext(mqpar$rawfile)) )
  if(nrow(mqpar) != 1){stop( paste("The mod/label information of the raw file ", MS2FileName, " extracted from mqpar.xml using the function readMQPar. [note:stopped in the function add_mod_aa].", sep="") )}
  empty = c("", NA, "NA")
  
  if(!mqpar$fixedModifications %in% empty ) { # contains fixed modifications
    Mod = unique(unlist(strsplit(mqpar$fixedModifications, ",")))
    
    modifications = mapply(extract_mod_xml, Mod, MoreArgs=list(mod_parameter_xml), SIMPLIFY=F) # Mod="Carbamidomethyl (C)"
    modifications = do.call(rbind, modifications) #
    
    # for modifications occurring dependent of specific AA
    aa_mw_table_fixed = subset(aa_mw_table, aa %in% modifications$mod_aa)
    if(nrow(aa_mw_table_fixed)>0){
      aa_mw_table_fixed = merge(aa_mw_table, modifications, by.x="aa", by.y= "mod_aa")
      aa_mw_table_fixed$weight =  as.numeric(aa_mw_table_fixed$mod_comp_mw) + as.numeric(aa_mw_table_fixed$weight)
      aa_mw_table_fixed=aa_mw_table_fixed[,c("aa", "weight", "aa_varmod", "labelmod","reporterion", "reporterion_group", "labelmod_group")]
      
      aa_mw_table = rbind( subset(aa_mw_table,! aa %in% modifications$mod_aa), aa_mw_table_fixed)
    }else{stop("The setting for fixed Modifications is wrong. Please contact the developer. [note:stopped in the function add_mod_aa].")}
  }
  
  aa_mw_mod_table = aa_mw_table
  
  if(!mqpar$variableModifications %in% empty ) { # contains variable modifications
    Mod = unique(unlist(strsplit(mqpar$variableModifications, ",")))
    
    modifications = mapply(extract_mod_xml, Mod, MoreArgs=list(mod_parameter_xml), SIMPLIFY=F) # Mod="Phospho (STY)"
    modifications = do.call(rbind, modifications) # df: Mod:Acetyl (Protein N-term); mod_abb:(ac); mod_comp_mw:42.01; mod_aa:-; mod_pos:proteinNterm
    
    # for modifications occurring dependent of specific AA
    aa_mw_table_mod = subset(aa_mw_table, aa %in% modifications$mod_aa)
    if(nrow(aa_mw_table_mod)>0){
      aa_mw_table_mod = merge(aa_mw_table_mod, modifications, by.x="aa", by.y= "mod_aa")
      aa_mw_table_mod$aa_varmod =  paste(aa_mw_table_mod$aa, aa_mw_table_mod$mod_abb, sep="")
      aa_mw_table_mod$weight =  as.numeric(aa_mw_table_mod$mod_comp_mw) + as.numeric(aa_mw_table_mod$weight)
      aa_mw_mod_table = rbind(aa_mw_table,aa_mw_table_mod[,c("aa", "weight", "aa_varmod", "labelmod","reporterion", "reporterion_group", "labelmod_group")])
    }
    # for modifications occurring independent of AA
    mod_anypos = subset(modifications, mod_aa %in% "-")
    if(nrow(mod_anypos) > 0){
      mod_anypos_left=apply(mod_anypos,1,calculate_aa_wm_anyTerminal, aa_mw_mod_table, flag = "variableModifications")
      mod_anypos_left = rbindlist(mod_anypos_left)
      aa_mw_mod_table = unique(rbind(aa_mw_mod_table, mod_anypos_left))
    }
  }
  if(!mqpar$isobaricLabels %in% empty ){ # contains reporter ion, e.g. TMT, iTRAQ; TMT10plex-Nter128,TMT10plex-Nter130,TMT10plex-Lys128,TMT10plex-Lys130
    #browser()
    Mods = unique(unlist(strsplit(mqpar$isobaricLabels, ",")))
    
    # read parameter.xml and collect isobaricLabels info
    #                      title              description   composition            type        mw
    # 1:              Acetyl (K)              Acetylation   C(2) H(2) O     Acetylation 42.010565
    # 2: Acetyl (Protein N-term)              Acetylation   C(2) H(2) O     Acetylation 42.010565
    # 3:     Carbamidomethyl (C) Iodoacetamide derivative C(2) H(3) N O   Iodoacetamide 57.021464
    xmlread = read_xml(mod_parameter_xml)
    children = xml_children(xmlread)
    mod_attrs=xml_attrs(children)
    mod_attrs = lapply(mod_attrs, function(x) as.data.table(t(x)))
    mod_attrs = rbindlist(mod_attrs)
    type_fr_description=strsplit(mod_attrs$description, " ")
    mod_attrs$type = unlist(lapply(type_fr_description, function(x) x[1]))
    mod_attrs$label=xml_text(xml_find_all(children, "type"))
    mod_attrs = mod_attrs[,c("title", "description","composition", "type")]
    
    calculate_composition<-function(composition){
      mod_comp_split = unlist(strsplit(composition, "\\s"))
      mod_comp_mw = sum(mapply(calculate_atom_mw, mod_comp_split)) # e.g. 15.99
    }
    
    mod_attrs$mw = mapply(calculate_composition, mod_attrs$composition)
    
    # extract the infomation of isobaricLabels included in mqpar.xml from parameter.xml
    # if isobaricLabels with same wm are clustered as a single string or separated and stored in a vector, by aggregate and paste
    isolabelType = unique(subset(mod_attrs, title %in% Mods, select=c(mw, type))) # group
    Mod_list=apply(isolabelType, 1, function(x) subset(mod_attrs, abs(mw - as.numeric(x["mw"]))<0.01 & type %in% x["type"])[1] ) # retain unique
    Mods = rbindlist(Mod_list)
    Mods=aggregate(Mods$title, by=list(Mods$mw), FUN=function(x) paste(x, collapse=";"), simplify=F)$x
    
    # For each cluster of isobaricLabels, add attach mw into aa_table
    aa_mw_mod_table = lapply(Mods, calculate_aa_wm_label, mod_parameter_xml, aa_mw_mod_table, flag="isobaricLabels")
    aa_mw_mod_table = rbindlist(aa_mw_mod_table)
    browser()
    
  }else if(!mqpar$labelMods %in% empty){ # contains labelMods, e.g. Dimethlys or SILAC
    Mods = unique(unlist(strsplit(mqpar$labelMods, ","))) # mods:Arg10;Lys8
    #browser()
    aa_mw_mod_table = lapply(Mods, calculate_aa_wm_label, mod_parameter_xml, aa_mw_mod_table, flag = "labelMods")
    aa_mw_mod_table = rbindlist(aa_mw_mod_table)
  }
  #browser()
  return(aa_mw_mod_table)
}



#extract_mod_xml function
extract_mod_xml <-function(Mod, xmlurl){
  xmlread = read_xml(xmlurl)
  xpath = paste("//modification[@title='",Mod,"']",sep = "")
  f1 = xml_find_all(xmlread,xpath)
  
  mod_pos = xml_text( xml_children(f1)[[1]] ) # position
  
  b=xml_find_all(f1[[1]] , "//*[name()='position']")
  cd=unique(xml_text(b))
  #browser()
  mod_comp = xml_attr(f1,"composition")
  mod_comp_split = unlist(strsplit(mod_comp, "\\s"))
  mod_comp_mw = sum(mapply(calculate_atom_mw, mod_comp_split)) # e.g. 15.99
  mod_abb = xml_attr(f1,"title")
  mod_abb = substr(mod_abb,1,2)
  mod_abb = tolower(mod_abb)             #e.g. ox
  mod_abb=paste("(",mod_abb,")", sep="") # e.g. "(ox)"
  
  f2 = xml_find_all(f1,"modification_site")
  mod_aa = xml_attr(f2,"site")
  mod_detail = data.table(cbind(Mod,mod_abb,mod_comp_mw, mod_aa, mod_pos),stringsAsFactors=F)
  return(mod_detail)
}

# calculate mod_aa at any Terminal
calculate_aa_wm_anyTerminal<-function(x, aa_mw_mod_table, flag, tmp=NA){
  #browser()
  mod_anypos = cbind(as.data.table(t(x)), aa_mw_mod_table) # merge two data.table by replicating mod_anypos for the nrow of aa_mw_mod_table
  #      Nterm = c("notCterm", "proteinNterm", "anywhere", "anyNterm", "anyCterm")
  mod_anypos_left=data.table()
  if(flag == "variableModifications"){
    mod_anypos_left = data.table(aa = mod_anypos$aa, weight = as.numeric(mod_anypos$mod_comp_mw) + as.numeric(mod_anypos$weight),
                                 aa_varmod= paste(mod_anypos$mod_abb, mod_anypos$aa_varmod, sep=""), labelmod = NA,
                                 reporterion = NA, reporterion_group = NA, labelmod_group = NA)
  }else if(flag == "isobaricLabels"){
    mod_anypos_left = data.table(aa = mod_anypos$aa, weight = as.numeric(mod_anypos$mod_comp_mw) + as.numeric(mod_anypos$weight),
                                 aa_varmod= mod_anypos$aa_varmod, labelmod = NA, labelmod_group = NA,
                                 reporterion = mod_anypos$mod_pos, reporterion_group = tmp)
  }else if(flag == "labelMods"){
    mod_anypos_left = data.table(aa = mod_anypos$aa, weight = as.numeric(mod_anypos$mod_comp_mw) + as.numeric(mod_anypos$weight),
                                 aa_varmod= mod_anypos$aa_varmod, labelmod = mod_anypos$mod_pos, labelmod_group = tmp,
                                 reporterion = NA, reporterion_group = NA )
  }
  return(mod_anypos_left)
}

# include general label and reportor ion labelling
calculate_aa_wm_label <-function(Mod, mod_parameter_xml, aa_mw_mod_table, flag){
  #browser()
  if(Mod != ""){
    Mod_invidual = unique(unlist(strsplit(Mod, ";")))
    modifications = mapply(extract_mod_xml, Mod_invidual, MoreArgs=list(mod_parameter_xml), SIMPLIFY=F) # Mod_invidual="Phospho (STY)"
    modifications = do.call(rbind, modifications)
    #browser()
    
    # for modifications occurring dependent of AA
    aa_mw_mod_table_label = subset(aa_mw_mod_table, aa %in% modifications$mod_aa)
    if(nrow(aa_mw_mod_table_label)>0){
      
      aa_mw_mod_table_label = merge(aa_mw_mod_table_label, modifications, by.x="aa", by.y= "mod_aa")
      aa_mw_mod_table_label$weight =  as.numeric(aa_mw_mod_table_label$mod_comp_mw) + as.numeric(aa_mw_mod_table_label$weight)
      
      aa_mw_mod_table_unlabel = subset(aa_mw_mod_table, ! aa %in% modifications$mod_aa)
      aa_mw_mod_table = rbind(aa_mw_mod_table_unlabel, aa_mw_mod_table_label[,c("aa", "weight", "aa_varmod", "labelmod", "reporterion", "reporterion_group", "labelmod_group")])
    }
    # for modifications occurring independent of AA
    mod_anypos = subset(modifications, mod_aa %in% "-")
    if(nrow(mod_anypos) > 0){
      if(flag == "isobaricLabels"){
        mod_anypos_left=apply(mod_anypos,1,calculate_aa_wm_anyTerminal, aa_mw_mod_table, flag ="isobaricLabels", tmp = Mod)
      }else if(flag == "labelMods"){
        mod_anypos_left=apply(mod_anypos,1,calculate_aa_wm_anyTerminal, aa_mw_mod_table, flag ="labelMods", tmp = Mod)
      }
      mod_anypos_left = rbindlist(mod_anypos_left)
      aa_mw_mod_table = unique(rbind(aa_mw_mod_table, mod_anypos_left))
    }
  }
  if(flag == "isobaricLabels"){
    aa_mw_mod_table$reporterion_group = rep(Mod, times=nrow(aa_mw_mod_table))
  }else if(flag == "labelMods"){
    aa_mw_mod_table$labelmod_group = rep(Mod, times=nrow(aa_mw_mod_table))
  }
  #browser()
  return(aa_mw_mod_table)
}


#calculate_atom_mw function for mod mw in extract_mod_xml
calculate_atom_mw <-function(atom){
  #browser()
  if(! grepl('\\(', atom)){ # without brackets
    atom_name = atom
    monoisotopic = atom_mw_table$Monoisotopic[which(atom_mw_table$Element==atom)]
  }else{
    atom_name = gsub('(.+)\\(.*$', '\\1', atom)
    monoisotopic = atom_mw_table$Monoisotopic[which(atom_mw_table$Element==atom_name)]
    atom_number = as.numeric(gsub('.+\\((.*)\\).*$', '\\1', atom))
    monoisotopic = monoisotopic * atom_number
  }
  if(length(monoisotopic) == 0 ){stop(paste("This atom type '", atom_name, "' has not been included in the package! Please contact the author! cd [note:stopped in the function calculate_atom_mw].", sep=""))}
  return(monoisotopic)
}
