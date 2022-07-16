function Get-SwissVM {
  Param ()
  
  # in the future we should handle excluding VM's that aren't created with SCL, but for now it's not a concern
  Get-VM

}
