package com.project.healthcare;

import org.springframework.data.jpa.repository.JpaRepository;

public interface MedicureRepository extends JpaRepository<Doctor,String>{

}
