package com.abigailovos.sales;

import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.annotation.DirtiesContext;

/** Runs the shared report contract only against a dedicated in-memory database. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:activity_report_contract;MODE=MySQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.flyway.enabled=false"
})
@AutoConfigureMockMvc
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class ActivityReportH2StorageTest extends ActivityReportStorageContract {}
