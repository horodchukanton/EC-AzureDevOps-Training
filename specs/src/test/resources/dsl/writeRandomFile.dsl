def projName = args.projectName
def resource = args.resourceName

def procedureName = 'WriteRandomFile'

project projName, {
    procedure procedureName, {
        resourceName = resource

        step 'RunProcedure', {
            shell = 'ec-groovy'
            command = '''
import java.io.*;
import java.util.*;

File file = new File("$[filepath]");
int size = Integer.valueOf("$[sizeKB]")

try {
    // Create file writer object
    writesToFile = new FileWriter(file);
    
    // Wrap the writer with buffered streams
    BufferedWriter writer = new BufferedWriter(writesToFile);
    int line;
    Random rand = new Random();
    for (int j = 0; j < size * 1024; j++) {
        // Randomize an integer and write it to the output file
        writer.write(rand.nextInt(255));
    }
    
    // Close the stream
    writer.close();
} 
catch (IOException e) {
    e.printStackTrace();
    System.exit(1);
}
 '''
        }

        formalParameter 'filepath', defaultValue: '', {
            type = "entry"
        }
        formalParameter 'sizeKB', defaultValue: '', {
            type = "entry"
        }


        // Custom properties
        filepath = ''
        sizeKB = ''
    }


}