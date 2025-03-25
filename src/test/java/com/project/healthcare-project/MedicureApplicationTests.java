package com.project.healthcare;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import com.project.healthcare.MedicureService;

@SpringBootTest
class MedicureApplicationTests {

	@Autowired
	MedicureService doctorService;
	
	@Test
	void contextLoads() {
	}
	
	@Test
	void testService() {
	  assertEquals(doctorService.sayHello(), "Hello from Doctor Shubham");
	}
}
